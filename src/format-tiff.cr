require "json"
require "num"

require "./tag"
require "./header"
require "./file"
require "./subfile"

# TODO: Write documentation for `Format::Tiff`
module Format::Tiff
  VERSION = "0.1.0"

  LITTLE_ENDIAN_CODE = "II".to_slice
  BIG_ENDIAN_CODE    = "MM".to_slice

  xray_parser = Tiff::File.new "./images/xray.tiff"
  ::File.write "./debug/xray-#{Time.local.to_unix}.json", xray_parser.to_pretty_json

  puts xray_parser.subfile.not_nil!.to_tensor.shape
end
