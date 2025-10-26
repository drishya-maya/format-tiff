class Format::Tiff::File
  class SubFile
    struct DirectoryEntry
      include JSON::Serializable

      @tag : Tag::Name
      @tag_code : UInt16
      @count : UInt32
      @type : Tag::Type
      @value_or_offset : UInt32

      def initialize(entry_bytes : Bytes, parser : Tiff::File)
        @tag = Tag::Name.new(parser.decode_2_bytes entry_bytes, start_at: 0)
        @tag_code = @tag.value

        @type = Tag::Type.new(parser.decode_2_bytes entry_bytes, start_at: 2)
        @count = parser.decode_4_bytes entry_bytes, start_at: 4

        @value_or_offset = parser.decode_4_bytes entry_bytes, start_at: 8
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

    def initialize(@directory_entries)

    end
  end
end
