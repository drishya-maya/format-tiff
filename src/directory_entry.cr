class Format::Tiff::File::SubFile
  class DirectoryEntry
    include JSON::Serializable

    getter tag : Tag::Name
    getter tag_code : UInt16
    @count : UInt32
    @type : Tag::Type
    getter value_or_offset : UInt32

    @[JSON::Field(ignore: true)]
    @parser : Tiff::File

    def initialize(@tag, @type, @count, @value_or_offset, @parser : Tiff::File)
      @tag_code = @tag.value
    end

    def initialize(entry_bytes : Bytes, @parser : Tiff::File)
      @tag = Tag::Name.new(@parser.decode_2_bytes(entry_bytes, start_at: 0))
      @tag_code = @tag.value

      @type = Tag::Type.new(@parser.decode_2_bytes(entry_bytes, start_at: 2))
      @count = @parser.decode_4_bytes(entry_bytes, start_at: 4)

      @value_or_offset = @parser.decode_4_bytes(entry_bytes, start_at: 8)
    end

    def read_long_fraction(parser)
      unless {Tag::Name::XResolution, Tag::Name::YResolution}.includes? @tag
        raise "Tag is not a resolution type"
      end

      parser.file_io.seek @value_or_offset, IO::Seek::Set
      numerator = parser.decode_4_bytes
      denominator = parser.decode_4_bytes

      numerator.to_f64 / denominator.to_f64
    end

    def write_long_fraction(numerator, denominator, writer)
      unless {Tag::Name::XResolution, Tag::Name::YResolution}.includes? @tag
        raise "Tag is not a resolution type"
      end

      writer.encode_4_bytes([numerator, denominator], seek_to: @value_or_offset) # value_or_offset
    end

    def read_longs(parser)
      unless {Tag::Name::StripOffsets, Tag::Name::StripByteCounts}.includes? @tag
        raise "Tag is not a strip offsets type"
      end

      if @count <= 1
        # values are stored directly in the value_or_offset field
        [@value_or_offset]
      else
        # values are stored at the offset location
        parser.file_io.seek @value_or_offset, IO::Seek::Set
        Array(UInt32).new(@count) do
          parser.decode_4_bytes
        end
      end
    end

    def write_longs(longs : Array(UInt32), writer)
      # if @count.size == 1
      #   writer.encode_4_bytes(longs[0])
      # else
        # parser.file_io.seek @value_or_offset, IO::Seek::Set
        # longs.each do |long|
        #   parser.encode_4_bytes(long)
        # end
        writer.encode_4_bytes longs, seek_to: @value_or_offset
      # end
    end

    def get_bytes(tiff_file)
      Bytes.new(12).tap do |buffer|
        tiff_file.endian_format.encode(@tag_code, buffer[0..1])
        tiff_file.endian_format.encode(@type.value, buffer[2..3])
        tiff_file.endian_format.encode(@count, buffer[4..7])
        tiff_file.endian_format.encode(@value_or_offset, buffer[8..11])
      end
    end
  end
end
