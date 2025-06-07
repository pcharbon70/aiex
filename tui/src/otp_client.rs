use anyhow::{Context, Result};
use rmp_serde as rmps;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::sync::mpsc;
use tokio::time;
use tracing::{debug, error, info, warn};

use crate::message::Message;

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum ClientMessage {
    #[serde(rename = "subscribe")]
    Subscribe { topic: String },
    
    #[serde(rename = "unsubscribe")]
    Unsubscribe { topic: String },
    
    #[serde(rename = "ping")]
    Ping,
    
    #[serde(rename = "request")]
    Request {
        id: String,
        command: String,
        params: HashMap<String, serde_json::Value>,
    },
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum ServerMessage {
    #[serde(rename = "welcome")]
    Welcome {
        client_id: u64,
        protocol_version: u8,
    },
    
    #[serde(rename = "message")]
    Message {
        topic: String,
        payload: serde_json::Value,
        timestamp: u64,
    },
    
    #[serde(rename = "subscribed")]
    Subscribed { topic: String },
    
    #[serde(rename = "unsubscribed")]
    Unsubscribed { topic: String },
    
    #[serde(rename = "pong")]
    Pong { timestamp: u64 },
    
    #[serde(rename = "response")]
    Response {
        id: String,
        result: serde_json::Value,
    },
}

/// OTP TCP client for communication with Elixir application
pub struct OtpClient {
    stream: Option<TcpStream>,
    pub server_addr: String,
    event_tx: mpsc::UnboundedSender<Message>,
    client_id: Option<u64>,
}

impl OtpClient {
    pub async fn new(
        server_addr: String,
        event_tx: mpsc::UnboundedSender<Message>,
    ) -> Result<Self> {
        let mut client = Self {
            stream: None,
            server_addr,
            event_tx,
            client_id: None,
        };

        // Attempt initial connection
        client.connect().await?;

        Ok(client)
    }

    async fn connect(&mut self) -> Result<()> {
        info!("Connecting to OTP server: {}", self.server_addr);

        match time::timeout(
            Duration::from_secs(10),
            TcpStream::connect(&self.server_addr),
        )
        .await
        {
            Ok(Ok(stream)) => {
                info!("Connected to OTP server successfully");
                self.stream = Some(stream);
                Ok(())
            }
            Ok(Err(e)) => {
                error!("Failed to connect to OTP server: {}", e);
                Err(e.into())
            }
            Err(_) => {
                error!("Connection timeout");
                Err(anyhow::anyhow!("Connection timeout"))
            }
        }
    }

    pub async fn run(&mut self) -> Result<()> {
        loop {
            if self.stream.is_none() {
                // Try to reconnect
                match self.connect().await {
                    Ok(_) => {
                        // Subscribe to default topics after reconnection
                        self.setup_subscriptions().await?;
                    }
                    Err(e) => {
                        warn!("Reconnection failed: {}", e);
                        time::sleep(Duration::from_secs(5)).await;
                        continue;
                    }
                }
            }

            if let Some(stream) = &mut self.stream {
                // Read message length (4 bytes)
                let mut len_buf = [0u8; 4];
                match stream.read_exact(&mut len_buf).await {
                    Ok(_) => {
                        let msg_len = u32::from_be_bytes(len_buf) as usize;
                        
                        // Read message data
                        let mut msg_buf = vec![0u8; msg_len];
                        match stream.read_exact(&mut msg_buf).await {
                            Ok(_) => {
                                // Decode MessagePack message
                                match rmps::from_slice::<ServerMessage>(&msg_buf) {
                                    Ok(msg) => {
                                        self.handle_server_message(msg).await?;
                                    }
                                    Err(e) => {
                                        error!("Failed to decode message: {}", e);
                                    }
                                }
                            }
                            Err(e) => {
                                error!("Failed to read message data: {}", e);
                                self.stream = None;
                                self.client_id = None;
                            }
                        }
                    }
                    Err(e) => {
                        error!("Failed to read message length: {}", e);
                        self.stream = None;
                        self.client_id = None;
                    }
                }
            }
        }
    }

    async fn handle_server_message(&mut self, msg: ServerMessage) -> Result<()> {
        match msg {
            ServerMessage::Welcome {
                client_id,
                protocol_version,
            } => {
                info!(
                    "Connected as client {} with protocol version {}",
                    client_id, protocol_version
                );
                self.client_id = Some(client_id);
                
                // Notify UI of connection
                self.event_tx
                    .send(Message::ConnectionStatus {
                        connected: true,
                        details: format!("Connected as client {}", client_id),
                    })
                    .context("Failed to send connection status")?;
            }
            
            ServerMessage::Message {
                topic,
                payload,
                timestamp: _,
            } => {
                debug!("Received message on topic {}: {:?}", topic, payload);
                
                // Convert to UI message based on topic
                if topic.starts_with("otp.event.") {
                    self.event_tx
                        .send(Message::OtpEvent {
                            event_type: topic.clone(),
                            data: payload,
                        })
                        .context("Failed to send OTP event")?;
                }
            }
            
            ServerMessage::Subscribed { topic } => {
                debug!("Subscribed to topic: {}", topic);
            }
            
            ServerMessage::Unsubscribed { topic } => {
                debug!("Unsubscribed from topic: {}", topic);
            }
            
            ServerMessage::Pong { timestamp: _ } => {
                debug!("Received pong");
            }
            
            ServerMessage::Response { id, result } => {
                debug!("Received response for request {}: {:?}", id, result);
                
                self.event_tx
                    .send(Message::CommandResult {
                        request_id: id,
                        result,
                    })
                    .context("Failed to send command result")?;
            }
        }
        
        Ok(())
    }

    async fn setup_subscriptions(&mut self) -> Result<()> {
        // Subscribe to default topics
        let topics = vec![
            "otp.event.pg.context_updates.join",
            "otp.event.pg.context_updates.leave",
            "otp.event.pg.model_responses.join",
            "otp.event.pg.interface_events.join",
        ];

        for topic in topics {
            self.subscribe(topic).await?;
        }

        Ok(())
    }

    pub async fn subscribe(&mut self, topic: &str) -> Result<()> {
        let msg = ClientMessage::Subscribe {
            topic: topic.to_string(),
        };
        self.send_message(&msg).await
    }

    pub async fn unsubscribe(&mut self, topic: &str) -> Result<()> {
        let msg = ClientMessage::Unsubscribe {
            topic: topic.to_string(),
        };
        self.send_message(&msg).await
    }

    pub async fn send_request(
        &mut self,
        id: String,
        command: String,
        params: HashMap<String, serde_json::Value>,
    ) -> Result<()> {
        let msg = ClientMessage::Request { id, command, params };
        self.send_message(&msg).await
    }

    async fn send_message(&mut self, msg: &ClientMessage) -> Result<()> {
        if let Some(stream) = &mut self.stream {
            let data = rmps::to_vec(msg).context("Failed to encode message")?;
            let len = data.len() as u32;
            
            // Write length prefix
            stream
                .write_all(&len.to_be_bytes())
                .await
                .context("Failed to write message length")?;
            
            // Write message data
            stream
                .write_all(&data)
                .await
                .context("Failed to write message data")?;
            
            stream.flush().await.context("Failed to flush stream")?;
            
            Ok(())
        } else {
            Err(anyhow::anyhow!("Not connected"))
        }
    }

    /// Start periodic ping to keep connection alive
    pub async fn start_heartbeat(mut self) {
        tokio::spawn(async move {
            let mut interval = time::interval(Duration::from_secs(30));
            
            loop {
                interval.tick().await;
                
                if self.stream.is_some() {
                    let msg = ClientMessage::Ping;
                    if let Err(e) = self.send_message(&msg).await {
                        warn!("Failed to send ping: {}", e);
                    }
                }
            }
        });
    }
}