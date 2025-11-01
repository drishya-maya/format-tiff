class Format::Tiff::File
  class SubFile
    include JSON::Serializable

    @tags_processed = false

    def initialize(@tags : Hash(Tag::Name, DirectoryEntry))
    end

    def process_tags(parser)
      return if @tags_processed

      @pixel_metadata = PixelMetadata.new @tags[Tag::Name::ImageWidth].value_or_offset,
                                          @tags[Tag::Name::ImageLength].value_or_offset,
                                          @tags[Tag::Name::SamplesPerPixel].value_or_offset.to_u16,
                                          @tags[Tag::Name::BitsPerSample].value_or_offset.to_u16,
                                          @tags[Tag::Name::PhotometricInterpretation].value_or_offset.to_u16

      @physical_dimensions = PhysicalDimensions.new @tags[Tag::Name::XResolution].read_long_fraction(parser),
                                                    @tags[Tag::Name::YResolution].read_long_fraction(parser),
                                                    @tags[Tag::Name::ResolutionUnit].value_or_offset.to_u16

      @data = Data.new @tags[Tag::Name::RowsPerStrip].value_or_offset,
                        @tags[Tag::Name::StripByteCounts].read_longs(parser), # strip_byte_counts
                        @tags[Tag::Name::StripOffsets].read_longs(parser), # strip_offsets
                        @tags[Tag::Name::Orientation].value_or_offset.to_u16,
                        @tags[Tag::Name::Compression].value_or_offset.to_u16

      @tags_processed = true
    end

    def to_a(parser)
      process_tags parser
      data = @data.not_nil!
      pixel_metadata = @pixel_metadata.not_nil!

      rows = [] of Array(UInt8)
      data.strip_offsets.each_with_index do |offset, index|
        parser.file_io.seek offset, IO::Seek::Set
        rows_to_decode = data.strip_byte_counts[index] // pixel_metadata.width

        rows += Array(Array(UInt8)).new(rows_to_decode) do
          parser.decode_1_bytes times: pixel_metadata.width
        end
      end

      rows
    end

    def to_tensor(parser)
      to_a(parser).to_tensor
    end

    def write(writer)
      @tags.values.sort_by(&.tag_code).each do |entry|
        entry.write(writer)
      end
    end

  end
end

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

    def write(writer)
      buffer = Bytes.new(12)
      writer.encode @tag_code, buffer[0..1]
      writer.encode @type.value, buffer[2..3]
      writer.encode @count, buffer[4..7]
      writer.encode @value_or_offset, buffer[8..11]

      writer.write buffer
    end
  end

  record PixelMetadata,
    width : UInt32,
    height : UInt32,
    samples_per_pixel : UInt16,
    bits_per_sample : UInt16,
    photometric : UInt16 {
      include JSON::Serializable
    }

  record PhysicalDimensions,
    # horizontal resolution in pixels per unit
    x_resolution : Float64,
    # vertical resolution in pixels per unit
    y_resolution : Float64,
    # unit of measurement
    resolution_unit : UInt16 {
      include JSON::Serializable
    }

  record Data,
    rows_per_strip : UInt32,
    strip_byte_counts : Array(UInt32),
    strip_offsets : Array(UInt32),
    # currently only orientation 1 (top-left) is supported
    orientation : UInt16,
    # currently only compression type 1 (no compression) is supported
    compression : UInt16 {
      include JSON::Serializable
    }
end
