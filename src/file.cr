class Format::Tiff::File
  include JSON::Serializable

  @[JSON::Field(ignore: true)]
  getter file_io : ::File

  getter file_path : String
  @header : Header
  getter subfile : SubFile?

  def initialize(@file_path : String)
    @file_io = ::File.open @file_path, "rb"
    @header = Header.new(read_buffer(@file_io, byte_size: 8))

    tags_count = decode_2_bytes @file_io, seek_to: @header.not_nil!.offset
    tags = Array(Tuple(Tag::Name, SubFile::DirectoryEntry)).new tags_count do
      entry_bytes = read_buffer @file_io, byte_size: 12
      directory_entry = SubFile::DirectoryEntry.new entry_bytes, self
      {directory_entry.tag, directory_entry}
    end.to_h

    # Baseline TIFF only has one subfile
    # Support for full TIFF specification can be added later
    @subfile = SubFile.new tags, self
  end

  def initialize(@file_path : String, tensor)
    @file_io = ::File.open @file_path, "wb"
    @header = Header.new
    # @header.write

    # @subfile = SubFile.new @tensor, self

  end

  delegate offset, to: @header

  macro generate_buffer_extraction_defs(byte_size)
    {% byte_bits = byte_size.id.to_i * 8 %}

    def read_buffer(file : ::File, byte_size)
      Bytes.new(byte_size).tap {|b| file.read_fully(b) }
    end

    def write_buffer(buffer : Bytes)
      @file_io.write buffer
    end

    def decode_{{byte_size}}_bytes(file : ::File)
      @header.not_nil!.endian_format.decode UInt{{byte_bits}}, read_buffer(file, {{byte_size}})
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

    def decode_{{byte_size}}_bytes(bytes : Slice(UInt8), start_at = 0)
      @header.not_nil!.endian_format.decode UInt{{byte_bits}}, bytes[start_at...start_at + {{byte_size}}]
    end
  end

  {% for byte_size in [1, 2, 4, 8] %}
    generate_buffer_extraction_defs {{byte_size}}
  {% end %}
end
