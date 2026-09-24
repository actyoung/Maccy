#!/usr/bin/ruby

source_dir, output_path = ARGV
abort "Usage: create-icns.rb SOURCE_DIR OUTPUT_PATH" unless source_dir && output_path

icons = [
  ["icp4", "AppIcon (Big Sur)-16w.png", 16],
  ["icp5", "AppIcon (Big Sur)-32w-1.png", 32],
  ["icp6", "AppIcon (Big Sur)-64w.png", 64],
  ["ic07", "AppIcon (Big Sur)-128w.png", 128],
  ["ic08", "AppIcon (Big Sur)-256w-1.png", 256],
  ["ic09", "AppIcon (Big Sur)-512w-1.png", 512],
  ["ic10", "AppIcon (Big Sur)-1024w.png", 1024],
  ["ic11", "AppIcon (Big Sur)-32w.png", 32],
  ["ic12", "AppIcon (Big Sur)-64w.png", 64],
  ["ic13", "AppIcon (Big Sur)-256w.png", 256],
  ["ic14", "AppIcon (Big Sur)-512w.png", 512]
]

png_signature = "\x89PNG\r\n\x1A\n".b
chunks = icons.map do |type, filename, expected_size|
  path = File.join(source_dir, filename)
  data = File.binread(path)
  abort "Invalid PNG: #{path}" unless data.start_with?(png_signature)

  width, height = data.byteslice(16, 8).unpack("NN")
  abort "Unexpected icon size: #{path}" unless width == expected_size && height == expected_size

  [type, data.bytesize + 8].pack("a4N") + data
end

payload = chunks.join
File.binwrite(output_path, ["icns", payload.bytesize + 8].pack("a4N") + payload)
