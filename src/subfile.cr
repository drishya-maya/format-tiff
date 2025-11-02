class Format::Tiff::File
  class SubFile
    include JSON::Serializable

    @tags_processed = false

    @[JSON::Field(ignore: true)]
    @context : Tiff::File::Context

    @tags : Hash(Tag::Name, Entry)

    def initialize(@context : Tiff::File::Context)
      @tags = extract_tags
    end

    def initialize(offset : UInt32, @context : Tiff::File::Context)
      @tags = extract_tags(offset)
    end

    def process_tags
      return if @tags_processed

      @pixel_metadata = PixelMetadata.new @tags[Tag::Name::ImageWidth].value_or_offset,
                                          @tags[Tag::Name::ImageLength].value_or_offset,
                                          @tags[Tag::Name::SamplesPerPixel].value_or_offset.to_u16,
                                          @tags[Tag::Name::BitsPerSample].value_or_offset.to_u16,
                                          @tags[Tag::Name::PhotometricInterpretation].value_or_offset.to_u16

      @physical_dimensions = PhysicalDimensions.new @tags[Tag::Name::XResolution].read_long_fraction,
                                                    @tags[Tag::Name::YResolution].read_long_fraction,
                                                    @tags[Tag::Name::ResolutionUnit].value_or_offset.to_u16

      @data = Data.new @tags[Tag::Name::RowsPerStrip].value_or_offset,
                        @tags[Tag::Name::StripByteCounts].read_longs, # strip_byte_counts
                        @tags[Tag::Name::StripOffsets].read_longs, # strip_offsets
                        @tags[Tag::Name::Orientation].value_or_offset.to_u16,
                        @tags[Tag::Name::Compression].value_or_offset.to_u16

      @tags_processed = true
    end

    def extract_tags(offset)
      tags_count = @context.read_u16_value start_offset: offset

      Array(Tuple(Tag::Name, Entry)).new tags_count do
        entry_bytes = @context.read_bytes 12
        directory_entry = Entry.new entry_bytes, @context
        {directory_entry.tag, directory_entry}
      end.to_h
    end

    def extract_tags
      tensor = @context.tensor.not_nil!
      raise "Invalid tensor shape" unless tensor.shape.size == 2

      tags = {} of Tag::Name => Entry

      tags[Tag::Name::NewSubfileType] = Entry.new(Tag::Name::NewSubfileType, Tag::Type::Long, 1_u32, 0, @context)
      tags[Tag::Name::PhotometricInterpretation] = Entry.new(Tag::Name::PhotometricInterpretation, Tag::Type::Short, 1_u32, 1_u32, @context)
      tags[Tag::Name::ImageDescription] = Entry.new(Tag::Name::ImageDescription, Tag::Type::Ascii, 0, 0, @context)

      image_height = tensor.shape[0]
      image_width = tensor.shape[1_u32]
      tags[Tag::Name::SamplesPerPixel] = Entry.new(Tag::Name::SamplesPerPixel, Tag::Type::Short, 1_u32, 1_u32, @context)
      tags[Tag::Name::BitsPerSample] = Entry.new(Tag::Name::BitsPerSample, Tag::Type::Short, 1_u32, 8, @context)
      tags[Tag::Name::ImageWidth] = Entry.new(Tag::Name::ImageWidth, Tag::Type::Long, 1_u32, image_width.to_u32, @context)
      tags[Tag::Name::ImageLength] = Entry.new(Tag::Name::ImageLength, Tag::Type::Long, 1_u32, image_height.to_u32, @context)

      subfile_end_offset = MAX_TAG_COUNT * DIRECTORY_ENTRY_SIZE + HEADER_SIZE + 1_u32
      x_resolution_offset = subfile_end_offset
      y_resolution_offset = x_resolution_offset + 8
      tags[Tag::Name::XResolution] = Entry.new(Tag::Name::XResolution, Tag::Type::Rational, 1_u32, subfile_end_offset, @context)
      tags[Tag::Name::YResolution] = Entry.new(Tag::Name::YResolution, Tag::Type::Rational, 1_u32, y_resolution_offset, @context)
      tags[Tag::Name::ResolutionUnit] = Entry.new(Tag::Name::ResolutionUnit, Tag::Type::Short, 1_u32, 3, @context)

      subfile_offsets_data_offset = subfile_end_offset + MAX_TAG_COUNT * MAX_TAG_TYPE_SIZE + 1_u32
      strip_count = (image_height / ROWS_PER_STRIP).ceil.to_u32
      # bytes_per_strip = image_width * ROWS_PER_STRIP

      tags[Tag::Name::Compression] = Entry.new(Tag::Name::Compression, Tag::Type::Short, 1_u32, 1_u32, @context)
      tags[Tag::Name::Orientation] = Entry.new(Tag::Name::Orientation, Tag::Type::Short, 1_u32, 1_u32, @context)
      tags[Tag::Name::RowsPerStrip] = Entry.new(Tag::Name::RowsPerStrip, Tag::Type::Long, 1_u32, ROWS_PER_STRIP, @context)
      tags[Tag::Name::StripOffsets] = Entry.new(Tag::Name::StripOffsets, Tag::Type::Long, strip_count, subfile_offsets_data_offset, @context)

      subfile_strip_data_offset = subfile_offsets_data_offset + strip_count * tags[Tag::Name::StripOffsets].type.bytesize
      tags[Tag::Name::StripByteCounts] = Entry.new(Tag::Name::StripByteCounts, Tag::Type::Long, strip_count, subfile_strip_data_offset, @context)

      tags
    end

    def to_a
      process_tags
      data = @data.not_nil!
      pixel_metadata = @pixel_metadata.not_nil!

      rows = [] of Array(UInt8)
      data.strip_offsets.each_with_index do |offset, index|
        @context.file_io.seek offset, IO::Seek::Set
        rows_to_decode = data.strip_byte_counts[index] // pixel_metadata.width

        rows += Array(Array(UInt8)).new(rows_to_decode) do
          @context.read_u8_values count: pixel_metadata.width
        end
      end

      rows
    end

    def to_tensor
      to_a.to_tensor
    end

    def get_directory_entry_bytes
      tag_count_bytes = @context.get_bytes(@tags.size.to_u16)
      @tags.values.sort_by(&.tag_code).reduce(tag_count_bytes) do |buffer, entry|
        buffer + entry.get_bytes
      end
    end

    def get_row_bytes(row : Tensor(UInt8, CPU(UInt8)))
      bytes = Bytes.new(row.size).tap do |row_bytes|
        row.each_with_index do |value, i|
          @context.endian_format.encode value, row_bytes[i..i]
        end
      end
      bytes
    end

    # TODO: Learn Tensor API and use performant functions for tensor iterations
    def get_strip_bytes(strip_index : Int)
      strip = @context.tensor.not_nil![(strip_index * ROWS_PER_STRIP)...((strip_index+1) * ROWS_PER_STRIP)]
      bytes = Bytes.empty

      strip.each_axis(0) do |row|
        bytes += get_row_bytes(row)
      end

      bytes
    end

    def get_all_strip_bytes
      all_strip_bytes = [] of Bytes

      @tags[Tag::Name::StripOffsets].count.times do |strip_index|
        all_strip_bytes << get_strip_bytes(strip_index)
      end

      all_strip_bytes
    end

    def get_resolution_bytes
      @tags[Tag::Name::XResolution].get_resolution_bytes + @tags[Tag::Name::YResolution].get_resolution_bytes
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
