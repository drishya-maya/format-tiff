require "json"
require "./header"
require "./parser"
require "./subfile"

# TODO: Write documentation for `Format::Tiff`
module Format::Tiff
  VERSION = "0.1.0"

  LITTLE_ENDIAN_CODE = "II".to_slice
  BIG_ENDIAN_CODE    = "MM".to_slice

  module Tag
    enum Name : UInt16
      # This is not used currently, but reserved for future use
      NewSubfileType = 254_u16
      ImageWidth = 256_u16
      ImageLength = 257_u16
      BitsPerSample = 258_u16
      Compression = 259_u16
      PhotometricInterpretation = 262_u16
      ImageDescription = 270_u16
      StripOffsets = 273_u16
      Orientation = 274_u16
      SamplesPerPixel = 277_u16
      RowsPerStrip = 278_u16
      StripByteCounts = 279_u16
      XResolution = 282_u16
      YResolution = 283_u16
      ResolutionUnit = 296_u16
    end

    enum Type : UInt16
      BYTE = 1_u16
      ASCII = 2_u16
      SHORT = 3_u16
      LONG = 4_u16
      RATIONAL = 5_u16

      def get_size
        case self
        when Type::BYTE, Type::ASCII
          1
        when Type::SHORT
          2
        when Type::LONG
          4
        when Type::RATIONAL
          8
        else
          raise "Unknown tag type"
        end
      end
    end
  end

  xray_parser = Format::Tiff::File.new "./images/xray.tiff"
  puts xray_parser.to_pretty_json
end
