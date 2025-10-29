class Format::Tiff::File
  class SubFile
    include JSON::Serializable

    @[JSON::Field(ignore: true)]
    # @parser : Tiff::File

    def initialize(@tags : Hash(Tag::Name, DirectoryEntry))
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

    def to_a(parser)
      rows = [] of Array(UInt8)
      @data.strip_offsets.each_with_index do |offset, index|
        parser.file_io.seek offset, IO::Seek::Set
        rows_to_decode = @data.strip_byte_counts[index] // @pixel_metadata.width

        rows += Array(Array(UInt8)).new(rows_to_decode) do
          parser.decode_1_bytes parser.file_io, times: @pixel_metadata.width
        end
      end

      rows
    end

    def to_tensor(parser)
      to_a(parser).to_tensor
    end

    # def initialize(tensor)
    #   # new_subfile_type - 0
    #   # image_width - tensor.shape[1]
    #   # image_length - tensor.shape[0]
    #   # bits_per_sample - 8
    #   # compression - 1
    #   # photometric_interpretation - 1
    #   # image_description - [\0]
    #   # rows_per_strip - 32
    #   # strip_offsets - []
    #   # strip_byte_counts - []
    #   # orientation - 1
    #   # samples_per_pixel - 1
    #   # x_resolution - 118.0
    #   # y_resolution - 118.0
    #   # resolution_unit - 3

    #   @parser.file_io.seek @header.offset, IO::Seek::Set
    #   Bytes.new(182).tap do |subfile_bytes|
    #     @parser.header.not_nil!.endian_format.encode(0_u16, subfile_bytes[0..1])                     # NewSubfileType
    #     @parser.header.not_nil!.endian_format.encode(@pixel_metadata.width, subfile_bytes[2..5])     # ImageWidth
    #     @parser.header.not_nil!.endian_format.encode(@pixel_metadata.height, subfile_bytes[6..9])    # ImageLength
    #     @parser.header.not_nil!.endian_format.encode(8_u16, subfile_bytes[10..11])                    # BitsPerSample
    #     @parser.header.not_nil!.endian_format.encode(1_u16, subfile_bytes[12..13])                    # Compression
    #     @parser.header.not_nil!.endian_format.encode(1_u16, subfile_bytes[14..15])                    # PhotometricInterpretation
    #     @parser.header.not_nil!.endian_format.encode(0_u32, subfile_bytes[16..19])                    # ImageDescription (offset)
    #     @parser.header.not_nil!.endian_format.encode(@data.rows_per_strip, subfile_bytes[20..23])    # RowsPerStrip
    #     @parser.header.not_nil!.endian_format.encode(0_u32, subfile_bytes[24..27])                    # StripOffsets (offset)
    #     @parser.header.not_nil!.endian_format.encode(0_u32, subfile_bytes[28..31])                    # StripByteCounts (offset)
    #     @parser.header.not_nil!.endian_format.encode(1_u16, subfile_bytes[32..33])                    # Orientation
    #     @parser.header.not_nil!.endian_format.encode(1_u16, subfile_bytes[34..35])                    # SamplesPerPixel
    #     @parser.header.not_nil!.endian_format.encode(118_u32, subfile_bytes[36..39])                  # XResolution (offset)
    #     @parser.header.not_nil!.endian_format.encode(118_u32, subfile_bytes[40..43])                  # YResolution (offset)
    #     @parser.header.not_nil!.endian_format.encode(3_u16, subfile_bytes[44..45])                    # ResolutionUnit

    #     @parser.write_buffer subfile_bytes
    #   end
    # end
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
