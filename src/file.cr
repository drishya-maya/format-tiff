class Format::Tiff::File
  include JSON::Serializable

  @[JSON::Field(ignore: true)]
  getter file_io : ::File

  getter file_path : String
  @header = Header.new
  getter subfile : SubFile?

  def initialize(@file_path : String)
    @file_io = ::File.open @file_path, "rb"
    @header = Header.new get_buffer @file_io, byte_size: 8

    tags_count = decode_2_bytes @file_io, seek_to: offset
    tags = Array(Tuple(Tag::Name, SubFile::DirectoryEntry)).new tags_count do
      entry_bytes = get_buffer @file_io, byte_size: 12
      directory_entry = SubFile::DirectoryEntry.new entry_bytes, self
      {directory_entry.tag, directory_entry}
    end.to_h

    # Baseline TIFF only has one subfile
    # Support for full TIFF specification can be added later
    @subfile = SubFile.new tags, self
  end

  delegate endian_format, offset, to: @header

  macro generate_buffer_extraction_defs(byte_size)
    {% byte_bits = byte_size.id.to_i * 8 %}

    def get_buffer(file : ::File, byte_size)
      Bytes.new(byte_size).tap {|b| file.read_fully(b) }
    end

    def decode_{{byte_size}}_bytes(file : ::File)
      endian_format.decode UInt{{byte_bits}}, get_buffer(file, {{byte_size}})
    end

    def decode_{{byte_size}}_bytes(file : ::File, *, times)
      Array(UInt{{byte_bits}}).new(times) do
        decode_{{byte_size}}_bytes(file)
      end
    end

    def decode_{{byte_size}}_bytes(file : ::File, *, seek_to)
      file.seek seek_to, IO::Seek::Set
      decode_{{byte_size}}_bytes(file)
    end

    def decode_{{byte_size}}_bytes(file : ::File, seek_to, times)
      file.seek seek_to, IO::Seek::Set
      Array(UInt{{byte_bits}}).new(times) do
        decode_{{byte_size}}_bytes(file)
      end
    end

    def decode_{{byte_size}}_bytes(bytes : Slice(UInt8), start_at)
      endian_format.decode UInt{{byte_bits}}, bytes[start_at...start_at + {{byte_size}}]
    end
  end

  {% for byte_size in [1, 2, 4, 8] %}
    generate_buffer_extraction_defs {{byte_size}}
  {% end %}
end
