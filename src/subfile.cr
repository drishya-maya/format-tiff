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

      def extract_resolution
        unless {Tag::Name::XResolution, Tag::Name::YResolution}.includes? @tag
          raise "Tag is not a resolution type"
        end

        @parser.file_io.seek @value_or_offset, IO::Seek::Set
        numerator = @parser.decode_4_bytes @parser.file_io
        denominator = @parser.decode_4_bytes @parser.file_io

        numerator.to_f64 / denominator.to_f64
      end

      # def extract_strip_offsets
      #   unless @tag == Tag::Name::StripOffsets
      #     raise "Tag is not a strip offsets type"
      #   end

      #   type_size = @type.get_size
      #   total_size = type_size * @count

      #   if total_size <= 4
      #     # values are stored directly in the value_or_offset field
      #     offsets = [] of UInt32
      #     start_at = 0
      #     {% for i in 0..3 %}
      #       if offsets.size < @count
      #         offset_value = @parser.decode_{{type_size}}_bytes(
      #           Bytes.new(4).tap {|b| @parser.endian_format.encode(@value_or_offset, b) },
      #           start_at
      #         ).to_u32
      #         offsets << offset_value
      #         start_at += {{type_size}}
      #       end
      #     {% end %}
      #     offsets
      #   else
      #     # values are stored at the offset location
      #     @parser.file_io.seek @value_or_offset, IO::Seek::Set
      #     Array(UInt32).new(@count) do
      #       @parser.decode_{{type_size}}_bytes(@parser.file_io).to_u32
      #     end
      #   end
      # end

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

      @physical_dimensions = PhysicalDimensions.new @tags[Tag::Name::XResolution].extract_resolution,
                                                    @tags[Tag::Name::YResolution].extract_resolution,
                                                    @tags[Tag::Name::ResolutionUnit].value_or_offset.to_u16

      # @data = Data.new @tags[Tag::Name::RowsPerStrip].value_or_offset,
      #                   [], # strip_byte_counts
      #                   [], # strip_offsets
      #                   @tags[Tag::Name::Orientation].value_or_offset,
      #                   @tags[Tag::Name::Compression].value_or_offset
    end
  end
end
