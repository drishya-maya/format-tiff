class Format::Tiff::File
  class Header
    include JSON::Serializable

    @[JSON::Field(ignore: true)]
    getter endian_format : IO::ByteFormat = IO::ByteFormat::LittleEndian
    @tiff_identifier = 0_u16
    getter offset = 9_u32

    @[JSON::Field(ignore: true)]
    @parser : Tiff::File

    def initialize(@parser)
    end

    def initialize(header_bytes : Bytes, @parser)
      @endian_format = get_byte_order header_bytes[0...2]
      # assert_tiff header_bytes[2...4]
      @tiff_identifier = @endian_format.decode UInt16, header_bytes[2...4]
      raise "Not a TIFF file" unless @tiff_identifier == TIFF_IDENTIFICATION_CODE

      @offset = @endian_format.decode UInt32, header_bytes[4...8]
    end

    def get_byte_order(endian_bytes : Bytes)
      case endian_bytes
      when LITTLE_ENDIAN_CODE_BYTES   then IO::ByteFormat::LittleEndian
      when BIG_ENDIAN_CODE_BYTES      then IO::ByteFormat::BigEndian
      else
        raise "Byte order information invalid"
      end
    end

    def get_byte_order_code_bytes
      if @endian_format == IO::ByteFormat::LittleEndian
        LITTLE_ENDIAN_CODE_BYTES
      elsif @endian_format == IO::ByteFormat::BigEndian
        BIG_ENDIAN_CODE_BYTES
      else
        raise "Byte order information invalid"
      end
    end

    def write
      # byte_order - endian_format
      # version - 42
      # offset - 9
      endian_bytes = get_byte_order_code_bytes


      @parser.write_buffer Bytes.new(8).tap { |header_bytes|
        endian_bytes.copy_to header_bytes[0..1]
        @endian_format.encode TIFF_IDENTIFICATION_CODE, header_bytes[2..3]
        @endian_format.encode @offset, header_bytes[4..7]
      }
    end
  end
end
