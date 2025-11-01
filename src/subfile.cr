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

    def get_directory_entry_bytes(tiff_file)
      tag_count_bytes = tiff_file.get_bytes(@tags.size.to_u16)
      @tags.values.sort_by(&.tag_code).reduce(tag_count_bytes) do |buffer, entry|
        buffer + entry.get_bytes(tiff_file)
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
