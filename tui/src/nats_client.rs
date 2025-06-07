use anyhow::{Context, Result};
use async_nats::{Client, ConnectOptions, Message as NatsMessage};
use futures::StreamExt;
use serde_json::Value;
use std::time::Duration;
use tokio::sync::mpsc;
use tracing::{debug, error, info, warn};

use crate::message::Message;

/// NATS client manager with robust connection handling and message processing
pub struct NatsManager {
    client: Option<Client>,
    nats_url: String,
    event_tx: mpsc::UnboundedSender<Message>,
}

impl NatsManager {
    pub async fn new(nats_url: String, event_tx: mpsc::UnboundedSender<Message>) -> Result<Self> {
        let mut manager = Self {
            client: None,
            nats_url,
            event_tx,
        };

        // Attempt initial connection
        manager.connect().await?;

        Ok(manager)
    }

    async fn connect(&mut self) -> Result<()> {
        info!("Connecting to NATS server: {}", self.nats_url);

        let options = ConnectOptions::new()
            .max_reconnects(None) // Infinite reconnects
            .reconnect_delay_callback(|attempts| {
                std::cmp::min(
                    Duration::from_millis(100 * 2_u64.pow(attempts.min(10) as u32)),
                    Duration::from_secs(30),
                )
            })
            .connection_timeout(Duration::from_secs(10))
            .name("aiex-tui");

        match options.connect(&self.nats_url).await {
            Ok(client) => {
                info!("Connected to NATS server successfully");
                self.client = Some(client);
                Ok(())
            }
            Err(e) => {
                error!("Failed to connect to NATS: {}", e);
                Err(e.into())
            }
        }
    }

    pub async fn start_message_processing(&mut self) -> Result<()> {
        if let Some(client) = self.client.clone() {
            info!("Starting NATS message processing");

            // Subscribe to OTP events
            self.subscribe_to_events(client.clone()).await?;

            // Start connection event monitoring
            self.start_connection_monitoring(client).await?;

            info!("NATS message processing started");
        }

        Ok(())
    }

    async fn subscribe_to_events(&mut self, client: Client) -> Result<()> {
        // Subscribe to all OTP events
        let event_tx = self.event_tx.clone();
        let mut otp_events = client.subscribe("otp.event.>").await?;

        tokio::spawn(async move {
            while let Some(message) = otp_events.next().await {
                if let Err(e) = Self::handle_nats_message(message, &event_tx).await {
                    error!("Error handling OTP event: {}", e);
                }
            }
        });

        // Subscribe to OTP responses
        let event_tx = self.event_tx.clone();
        let mut otp_responses = client.subscribe("otp.response.>").await?;

        tokio::spawn(async move {
            while let Some(message) = otp_responses.next().await {
                if let Err(e) = Self::handle_nats_message(message, &event_tx).await {
                    error!("Error handling OTP response: {}", e);
                }
            }
        });

        info!("Subscribed to NATS topics");
        Ok(())
    }

    async fn start_connection_monitoring(&self, _client: Client) -> Result<()> {
        // Connection monitoring simplified for now
        // The async-nats library has changed its API
        let event_tx = self.event_tx.clone();
        
        tokio::spawn(async move {
            // Send initial connected event
            if let Err(e) = event_tx.send(Message::NatsMessage {
                topic: "system.connection.connected".to_string(),
                data: vec![],
            }) {
                error!("Failed to send connection event: {}", e);
            }
        });

        Ok(())
    }

    async fn handle_nats_message(
        message: NatsMessage,
        event_tx: &mpsc::UnboundedSender<Message>,
    ) -> Result<()> {
        let topic = message.subject.to_string();
        let data = message.payload.to_vec();

        debug!("Received NATS message on topic: {}", topic);

        // Route based on topic patterns
        if topic.starts_with("otp.event.file.changed") {
            Self::handle_file_changed_event(data, event_tx).await?;
        } else if topic.starts_with("otp.event.build.completed") {
            Self::handle_build_completed_event(data, event_tx).await?;
        } else {
            // Generic message handling
            if let Err(e) = event_tx.send(Message::NatsMessage { topic, data }) {
                error!("Failed to send NATS message: {}", e);
            }
        }

        Ok(())
    }

    async fn handle_file_changed_event(
        data: Vec<u8>,
        event_tx: &mpsc::UnboundedSender<Message>,
    ) -> Result<()> {
        // Deserialize file change event
        let event: Value = rmp_serde::from_slice(&data)
            .context("Failed to deserialize file changed event")?;

        if let (Some(path), Some(content)) = (
            event.get("file_path").and_then(|v| v.as_str()),
            event.get("content").and_then(|v| v.as_str()),
        ) {
            if let Err(e) = event_tx.send(Message::FileChanged {
                path: path.to_string(),
                content: content.to_string(),
            }) {
                error!("Failed to send file changed message: {}", e);
            }
        }

        Ok(())
    }

    async fn handle_build_completed_event(
        data: Vec<u8>,
        event_tx: &mpsc::UnboundedSender<Message>,
    ) -> Result<()> {
        // Deserialize build completed event
        let event: Value = rmp_serde::from_slice(&data)
            .context("Failed to deserialize build completed event")?;

        if let (Some(status), Some(output)) = (
            event.get("status").and_then(|v| v.as_str()),
            event.get("output").and_then(|v| v.as_str()),
        ) {
            if let Err(e) = event_tx.send(Message::BuildCompleted {
                status: status.to_string(),
                output: output.to_string(),
            }) {
                error!("Failed to send build completed message: {}", e);
            }
        }

        Ok(())
    }

    pub async fn publish(&self, subject: String, data: Value) -> Result<()> {
        if let Some(ref client) = self.client {
            let encoded_data = rmp_serde::to_vec(&data)
                .context("Failed to serialize message data")?;

            client.publish(subject, encoded_data.into()).await
                .context("Failed to publish NATS message")?;

            debug!("Published message to topic");
        } else {
            warn!("Cannot publish message - not connected to NATS");
        }

        Ok(())
    }

    pub async fn request(&self, subject: String, data: Value) -> Result<NatsMessage> {
        if let Some(ref client) = self.client {
            let encoded_data = rmp_serde::to_vec(&data)
                .context("Failed to serialize request data")?;

            let response = client
                .request(subject, encoded_data.into())
                .await
                .context("Failed to send NATS request")?;

            debug!("Received response for request");
            Ok(response)
        } else {
            anyhow::bail!("Cannot send request - not connected to NATS");
        }
    }

    pub async fn request_with_timeout(
        &self,
        subject: String,
        data: Value,
        timeout: Duration,
    ) -> Result<NatsMessage> {
        if let Some(ref client) = self.client {
            let encoded_data = rmp_serde::to_vec(&data)
                .context("Failed to serialize request data")?;

            let response = tokio::time::timeout(
                timeout,
                client.request(subject, encoded_data.into()),
            )
            .await
            .context("Request timed out")?
            .context("Failed to send NATS request")?;

            debug!("Received response for request");
            Ok(response)
        } else {
            anyhow::bail!("Cannot send request - not connected to NATS");
        }
    }

    pub fn is_connected(&self) -> bool {
        self.client.is_some()
    }
}