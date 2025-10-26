# class UInt32
#   def call(method_name : Symbol)
#     case method_name
#     when :to_u8
#       to_u8
#     when :to_u16
#       to_u16
#     when :to_u32
#       to_u32
#     when :to_u64
#       to_u64
#     else
#       raise "Unsupported conversion"
#     end
#   end
# end

class Format::Tiff::File
  class SubFile
    @tags : Hash(Tag::Name, DirectoryEntry)

    struct DirectoryEntry
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

      def get_value
        if @type.get_size * @count <= 4
          case @type.get_int_type
          when UInt8
            @value_or_offset.to_u8
          when UInt16
            @value_or_offset.to_u16
          when UInt32
            @value_or_offset.to_u32
          when UInt64
            @value_or_offset.to_u64
          else
            raise "Unsupported integer type"
          end
        else
          case @tag
          when Tag::Name::StripByteCounts
            1
          when Tag::Name::StripOffsets
            Array(UInt32).new(@count) do |i|
              @parser.decode_4_bytes(@parser.file_io, seek_to: @value_or_offset)
            end
          else
            raise "Unsupported tag for value extraction"
          end
        end
      end
    end

    record(
      PixelMetadata,
      # pixel count per scanline
      width : UInt32,
      # scanlines count
      height : UInt32,
      # components per pixel
      samples_per_pixel : UInt16,
      # bits per component
      bits_per_sample : UInt16,
      # photometric interpretation
      photometric : UInt16
    )

    record(
      PhysicalDimensions,
      # horizontal resolution in pixels per unit
      x_resolution : Float64,
      # vertical resolution in pixels per unit
      y_resolution : Float64,
      # unit of measurement
      resolution_unit : UInt16
    )

    record(
      Data,
      rows_per_strip : UInt32,
      strip_byte_counts : Array(UInt32),
      strip_offsets : Array(UInt32),
      # currently only orientation 1 (top-left) is supported
      orientation : UInt16,
      # currently only compression type 1 (no compression) is supported
      compression : UInt16
    )

    def initialize(@tags)
      @pixel_metadata = PixelMetadata.new @tags[Tag::Name::ImageWidth].value_or_offset,
                                          @tags[Tag::Name::ImageLength].value_or_offset,
                                          @tags[Tag::Name::SamplesPerPixel].value_or_offset.to_u16,
                                          @tags[Tag::Name::BitsPerSample].value_or_offset.to_u16,
                                          @tags[Tag::Name::PhotometricInterpretation].value_or_offset.to_u16

      # @physical_dimensions = PhysicalDimensions.new @tags[Tag::Name::XResolution].value_or_offset.to_u32,
      #                                               @tags[Tag::Name::YResolution].value_or_offset,
      #                                               @tags[Tag::Name::ResolutionUnit].value_or_offset

      # @data = Data.new @tags[Tag::Name::RowsPerStrip].value_or_offset,
      #                   [], # strip_byte_counts
      #                   [], # strip_offsets
      #                   @tags[Tag::Name::Orientation].value_or_offset,
      #                   @tags[Tag::Name::Compression].value_or_offset
    end
  end
end
