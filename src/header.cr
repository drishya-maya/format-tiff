class Format::Tiff::File
  class Header
    include JSON::Serializable

    @[JSON::Field(ignore: true)]
    @endian_format : IO::ByteFormat = IO::ByteFormat::LittleEndian
    @tiff_identifier = 0_u16
    getter offset = 0_u32

    @[JSON::Field(ignore: true)]

    def initialize(@endian_format, @tiff_identifier, @offset)
    end

    def initialize(@endian_format, @tiff_identifier)
    end

    def get_bytes
      endian_bytes = Tiff.get_endian_code_bytes @endian_format

      Bytes.new(8).tap { |header_bytes|
        endian_bytes.copy_to header_bytes[0..1]
        @endian_format.encode TIFF_IDENTIFICATION_CODE, header_bytes[2..3]
        @endian_format.encode @offset, header_bytes[4..7]
      }
    end
  end
end
