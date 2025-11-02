require "json"
require "num"

require "./tag"
require "./header"
require "./file"
require "./context"
require "./directory_entry"
require "./subfile"

# TODO: Write documentation for `Format::Tiff`
module Format::Tiff
  VERSION = "0.1.0"

  LITTLE_ENDIAN_CODE_BYTES = "II".to_slice
  BIG_ENDIAN_CODE_BYTES    = "MM".to_slice
  TIFF_IDENTIFICATION_CODE = 42_u16

  MAX_TAG_COUNT = 75_u32 # TIFF v6 defines
  HEADER_SIZE = 8_u32
  DIRECTORY_ENTRY_SIZE = 12_u32
  MAX_TAG_TYPE_SIZE = 8_u32 # for example, rational type


  xray_parser = Tiff::File.new "./images/xray.tiff"
  ::File.write "./debug/xray-#{Time.local.to_unix}.json", xray_parser.to_pretty_json

  image_tensor = xray_parser.to_tensors
  # debugger

  xray_writer = Tiff::File.new image_tensor, "./images/xray-copy.tiff"
  xray_writer.get_bytes
  # xray_writer.write
end
