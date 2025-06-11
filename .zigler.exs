# Zigler configuration
[
  # Specify the path to Zig source files
  zig_source_path: "c_src",
  
  # Specify Zig version (optional, will use system default if not specified)
  # zig_version: "0.11.0",
  
  # Additional build flags
  build_flags: [
    # "-Doptimize=ReleaseFast"
  ],
  
  # NIF version compatibility
  nif_version: "2.16"
]