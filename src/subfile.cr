class Format::Tiff::File
  class SubFile
    # @tags : Hash(Tag::Name, DirectoryEntry)
    include JSON::Serializable

    @[JSON::Field(ignore: true)]
    @parser : Tiff::File

    def initialize(@tags : Hash(Tag::Name, DirectoryEntry), @parser : Tiff::File)
      @pixel_metadata = PixelMetadata.new @tags[Tag::Name::ImageWidth].value_or_offset,
                                          @tags[Tag::Name::ImageLength].value_or_offset,
                                          @tags[Tag::Name::SamplesPerPixel].value_or_offset.to_u16,
                                          @tags[Tag::Name::BitsPerSample].value_or_offset.to_u16,
                                          @tags[Tag::Name::PhotometricInterpretation].value_or_offset.to_u16

      @physical_dimensions = PhysicalDimensions.new @tags[Tag::Name::XResolution].extract_long_fraction,
                                                    @tags[Tag::Name::YResolution].extract_long_fraction,
                                                    @tags[Tag::Name::ResolutionUnit].value_or_offset.to_u16

      @data = Data.new @tags[Tag::Name::RowsPerStrip].value_or_offset,
                        @tags[Tag::Name::StripByteCounts].extract_longs, # strip_byte_counts
                        @tags[Tag::Name::StripOffsets].extract_longs, # strip_offsets
                        @tags[Tag::Name::Orientation].value_or_offset.to_u16,
                        @tags[Tag::Name::Compression].value_or_offset.to_u16
    end

    def to_a
      rows = [] of Array(UInt8)
      @data.strip_offsets.each_with_index do |offset, index|
        @parser.file_io.seek offset, IO::Seek::Set
        rows_to_decode = @data.strip_byte_counts[index] // @pixel_metadata.width

        rows += Array(Array(UInt8)).new(rows_to_decode) do
          @parser.decode_1_bytes @parser.file_io, times: @pixel_metadata.width
        end
      end

      rows
    end
  end
end

class Format::Tiff::File::SubFile
  class DirectoryEntry
    include JSON::Serializable

    getter tag : Tag::Name
    @tag_code : UInt16
    @count : UInt32
    @type : Tag::Type
    getter value_or_offset : UInt32

    @[JSON::Field(ignore: true)]
    @parser : Tiff::File

    def initialize(entry_bytes : Bytes, @parser : Tiff::File)
      @tag = Tag::Name.new(@parser.decode_2_bytes(entry_bytes, start_at: 0))
      @tag_code = @tag.value

      @type = Tag::Type.new(@parser.decode_2_bytes(entry_bytes, start_at: 2))
      @count = @parser.decode_4_bytes(entry_bytes, start_at: 4)

      @value_or_offset = @parser.decode_4_bytes(entry_bytes, start_at: 8)
    end

    def extract_long_fraction
      unless {Tag::Name::XResolution, Tag::Name::YResolution}.includes? @tag
        raise "Tag is not a resolution type"
      end

      @parser.file_io.seek @value_or_offset, IO::Seek::Set
      numerator = @parser.decode_4_bytes @parser.file_io
      denominator = @parser.decode_4_bytes @parser.file_io

      numerator.to_f64 / denominator.to_f64
    end

    def extract_longs
      unless {Tag::Name::StripOffsets, Tag::Name::StripByteCounts}.includes? @tag
        raise "Tag is not a strip offsets type"
      end

      if @count <= 1
        # values are stored directly in the value_or_offset field
        [@value_or_offset]
      else
        # values are stored at the offset location
        @parser.file_io.seek @value_or_offset, IO::Seek::Set
        Array(UInt32).new(@count) do
          @parser.decode_4_bytes @parser.file_io
        end
      end
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
