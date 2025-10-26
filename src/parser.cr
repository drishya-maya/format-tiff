module Format::Tiff
  class File
    include JSON::Serializable

    @[JSON::Field(ignore: true)]
    getter file_io : ::File
    getter file_path : String
    @header = Tiff::Header.new
    @directory_entries = [] of Tiff::SubFile::DirectoryEntry

    def initialize(@file_path : String)
      @file_io = ::File.open @file_path, "rb"
      @header = Tiff::Header.new get_buffer @file_io, byte_size: 8

      directory_entries_count = decode_2_bytes @file_io, seek_to: offset
      @directory_entries = Array(Tiff::SubFile::DirectoryEntry).new directory_entries_count do
        entry_bytes = get_buffer @file_io, byte_size: 12
        Tiff::SubFile::DirectoryEntry.new entry_bytes, self
      end

      # pixel_dimensions = PixelMetadata.new
      # physical_dimensions = PhysicalDimensions.new
      # data = Data.new
    end

    delegate endian_format, offset, to: @header

    macro generate_buffer_extraction_defs(byte_size)
      {% byte_bits = byte_size.id.to_i * 8 %}

      def get_buffer(file : ::File, byte_size)
        Bytes.new(byte_size).tap {|b| file.read_fully(b) }
      end

      def get_buffer(file : ::File, seek_to, byte_size)
        file.seek seek_to, IO::Seek::Set
        Bytes.new(byte_size).tap {|b| file.read_fully(b) }
      end

      def decode_{{byte_size}}_bytes(file : ::File)
        endian_format.decode UInt{{byte_bits}}, get_buffer(file, {{byte_size}})
      end

      def decode_{{byte_size}}_bytes(file : ::File, seek_to)
        file.seek seek_to, IO::Seek::Set
        endian_format.decode UInt{{byte_bits}}, get_buffer(file, {{byte_size}})
      end

      def decode_{{byte_size}}_bytes(bytes : Slice(UInt8), start_at)
        endian_format.decode UInt{{byte_bits}}, bytes[start_at...start_at + {{byte_size}}]
      end
    end

    {% for byte_size in [1, 2, 4, 8] %}
      generate_buffer_extraction_defs {{byte_size}}
    {% end %}
  end
end
