module Format::Tiff
  class Header
    include JSON::Serializable

    @[JSON::Field(ignore: true)]
    getter endian_format : IO::ByteFormat = IO::ByteFormat::LittleEndian
    getter offset = 0u32

    def initialize
    end

    def initialize(header_bytes : Bytes)
      @endian_format = get_byte_order header_bytes[0...2]
      assert_tiff header_bytes[2...4]
      @offset = @endian_format.decode UInt32, header_bytes[4...8]
    end

    def get_byte_order(endian_bytes : Bytes)
      case endian_bytes
      when LITTLE_ENDIAN_CODE   then IO::ByteFormat::LittleEndian
      when BIG_ENDIAN_CODE      then IO::ByteFormat::BigEndian
      else
        raise "Byte order information invalid"
      end
    end

    def assert_tiff(identification_bytes : Bytes)
      unless identification_bytes == Bytes.new(2).tap {|b| @endian_format.encode 42_u8, b }
        raise "Not a TIFF file"
      end
    end
  end
end
