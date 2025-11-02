class Format::Tiff::File::SubFile
  class DirectoryEntry
    include JSON::Serializable

    getter tag : Tag::Name
    getter tag_code : UInt16
    getter count : UInt32
    getter type : Tag::Type
    getter value_or_offset : UInt32

    @[JSON::Field(ignore: true)]
    @context : Tiff::File::Context

    def initialize(@tag, @type, @count, @value_or_offset, @context : Tiff::File::Context)
      @tag_code = @tag.value
    end

    def initialize(entry_bytes : Bytes, @context : Tiff::File::Context)
      @tag = Tag::Name.new @context.read_u16_value from: entry_bytes, start_offset: 0
      @tag_code = @tag.value

      @type = Tag::Type.new @context.read_u16_value from: entry_bytes, start_offset: 2
      @count = @context.read_u32_value from: entry_bytes, start_offset: 4

      @value_or_offset = @context.read_u32_value from: entry_bytes, start_offset: 8
    end

    def read_long_fraction
      unless {Tag::Name::XResolution, Tag::Name::YResolution}.includes? @tag
        raise "Tag is not a resolution type"
      end

      @context.file_io.seek @value_or_offset, IO::Seek::Set
      numerator = @context.read_u32_value
      denominator = @context.read_u32_value

      numerator.to_f64 / denominator.to_f64
    end

    def write_long_fraction(numerator, denominator, writer)
      unless {Tag::Name::XResolution, Tag::Name::YResolution}.includes? @tag
        raise "Tag is not a resolution type"
      end

      writer.encode_4_bytes([numerator, denominator], seek_to: @value_or_offset) # value_or_offset
    end

    def read_longs
      unless {Tag::Name::StripOffsets, Tag::Name::StripByteCounts}.includes? @tag
        raise "Tag is not a strip offsets type"
      end

      if @count <= 1
        # values are stored directly in the value_or_offset field
        [@value_or_offset]
      else
        # values are stored at the offset location
        @context.file_io.seek @value_or_offset, IO::Seek::Set
        Array(UInt32).new(@count) do
          @context.read_u32_value
        end
      end
    end

    def write_longs(longs : Array(UInt32), writer)
        writer.encode_4_bytes longs, seek_to: @value_or_offset
    end

    def get_bytes
      Bytes.new(12).tap do |buffer|
        @context.endian_format.encode(@tag_code, buffer[0..1])
        @context.endian_format.encode(@type.value, buffer[2..3])
        @context.endian_format.encode(@count, buffer[4..7])
        @context.endian_format.encode(@value_or_offset, buffer[8..11])
      end
    end

    def get_resolution_bytes
      unless @tag == Tag::Name::XResolution || @tag == Tag::Name::YResolution
        raise "Tag is not XResolution or YResolution type"
      end

      Bytes.new(8).tap do |bytes|
        @context.endian_format.encode(118_u32, bytes[0..3])
        @context.endian_format.encode(1_u32, bytes[4..7])
      end
    end
  end
end
