# fisrt write data to bytes/tags then to write to file.
require "json"
require "num"

require "./tag"
require "./header"
require "./file"
require "./context"
require "./directory_entry"
require "./subfile"

# TODO: Write documentation for `Format::Tiff`
module Format

  def self.get_printable(bytes, base = 16, size_threshold_for_compaction = 8)
    if bytes.size <= size_threshold_for_compaction
      bytes.map(&.to_s(base).rjust(2, '0')).join(' ')
    else
      bytes[0..3].map(&.to_s(base).rjust(2, '0')).join(' ') + ", ..., " + bytes[-4..-1].map(&.to_s(base).rjust(2, '0')).join(' ')
    end
  end

  module Tiff
    VERSION = "0.1.0"

    {% if flag?(:trace) %}
      Log.setup(:trace)
    {% end %}

    LITTLE_ENDIAN_CODE_BYTES = "II".to_slice
    BIG_ENDIAN_CODE_BYTES    = "MM".to_slice
    TIFF_IDENTIFICATION_CODE = 42_u16

    MAX_TAG_COUNT = 75_u32 # TIFF v6 defines
    HEADER_SIZE = 8_u32
    DIRECTORY_ENTRY_SIZE = 12_u32
    MAX_TAG_TYPE_SIZE = 8_u32 # for example, rational type

    def self.get_endianness(endian_code_bytes : Bytes)
      case endian_code_bytes
      when LITTLE_ENDIAN_CODE_BYTES   then IO::ByteFormat::LittleEndian
      when BIG_ENDIAN_CODE_BYTES      then IO::ByteFormat::BigEndian
      else
        raise "Byte order information invalid."
      end
    end

    def self.get_endian_code_bytes(endianness : IO::ByteFormat)
      if endianness == IO::ByteFormat::LittleEndian
        LITTLE_ENDIAN_CODE_BYTES
      elsif endianness == IO::ByteFormat::BigEndian
        BIG_ENDIAN_CODE_BYTES
      else
        raise "Byte order information invalid."
      end
    end

    # TODO: replace this with unit tests
    # xray_parser = Tiff::File.new "./images/xray.tif"
    # ::File.write "./debug/xray-#{Time.local.to_unix}.json", xray_parser.to_pretty_json
    # image_tensor = xray_parser.to_tensors
    # Log.info &.emit "Parsed image tensor:", shape: image_tensor.shape, tensor: image_tensor.to_s

    # xray_writer = Tiff::File.new image_tensor
    # xray_writer.write("./images/xray-copy.tiff")
  end
end
