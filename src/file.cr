# TODO: Nicely add comments and documentation in entire repo
class Format::Tiff::File
  include JSON::Serializable

  Log = ::Log.for("tiff-file", level: :trace)

  alias Entry = Format::Tiff::File::SubFile::DirectoryEntry
  ROWS_PER_STRIP = 32_u32

  @[JSON::Field(ignore: true)]
  getter file_io : ::File

  getter file_path : String
  @header : Header
  getter subfile : SubFile?

  @[JSON::Field(ignore: true)]
  getter tensor : Tensor(UInt8, CPU(UInt8))?

  def extract_tags(from : ::File)
    tags_count = decode_2_bytes seek_to: offset

    Array(Tuple(Tag::Name, Entry)).new tags_count do
      entry_bytes = read_buffer byte_size: 12
      directory_entry = Entry.new entry_bytes, self
      {directory_entry.tag, directory_entry}
    end.to_h
  end

  def extract_tags(from : Tensor(UInt8, CPU(UInt8)))
    tensor = from
    raise "Invalid tensor shape" unless tensor.shape.size == 2

    tags = {} of Tag::Name => Entry

    tags[Tag::Name::NewSubfileType] = Entry.new(Tag::Name::NewSubfileType, Tag::Type::Long, 1_u32, 0, self)
    tags[Tag::Name::PhotometricInterpretation] = Entry.new(Tag::Name::PhotometricInterpretation, Tag::Type::Short, 1_u32, 1_u32, self)
    tags[Tag::Name::ImageDescription] = Entry.new(Tag::Name::ImageDescription, Tag::Type::Ascii, 0, 0, self)

    image_height = tensor.shape[0]
    image_width = tensor.shape[1_u32]
    tags[Tag::Name::SamplesPerPixel] = Entry.new(Tag::Name::SamplesPerPixel, Tag::Type::Short, 1_u32, 1_u32, self)
    tags[Tag::Name::BitsPerSample] = Entry.new(Tag::Name::BitsPerSample, Tag::Type::Short, 1_u32, 8, self)
    tags[Tag::Name::ImageWidth] = Entry.new(Tag::Name::ImageWidth, Tag::Type::Long, 1_u32, image_width.to_u32, self)
    tags[Tag::Name::ImageLength] = Entry.new(Tag::Name::ImageLength, Tag::Type::Long, 1_u32, image_height.to_u32, self)

    subfile_end_offset = MAX_TAG_COUNT * DIRECTORY_ENTRY_SIZE + HEADER_SIZE + 1_u32
    x_resolution_offset = subfile_end_offset
    y_resolution_offset = x_resolution_offset + 8
    tags[Tag::Name::XResolution] = Entry.new(Tag::Name::XResolution, Tag::Type::Rational, 1_u32, subfile_end_offset, self)
    tags[Tag::Name::YResolution] = Entry.new(Tag::Name::YResolution, Tag::Type::Rational, 1_u32, y_resolution_offset, self)
    tags[Tag::Name::ResolutionUnit] = Entry.new(Tag::Name::ResolutionUnit, Tag::Type::Short, 1_u32, 3, self)

    subfile_offsets_data_offset = subfile_end_offset + MAX_TAG_COUNT * MAX_TAG_TYPE_SIZE + 1_u32
    strip_count = (image_height / ROWS_PER_STRIP).ceil.to_u32
    # bytes_per_strip = image_width * ROWS_PER_STRIP

    tags[Tag::Name::Compression] = Entry.new(Tag::Name::Compression, Tag::Type::Short, 1_u32, 1_u32, self)
    tags[Tag::Name::Orientation] = Entry.new(Tag::Name::Orientation, Tag::Type::Short, 1_u32, 1_u32, self)
    tags[Tag::Name::RowsPerStrip] = Entry.new(Tag::Name::RowsPerStrip, Tag::Type::Long, 1_u32, ROWS_PER_STRIP, self)
    tags[Tag::Name::StripOffsets] = Entry.new(Tag::Name::StripOffsets, Tag::Type::Long, strip_count, subfile_offsets_data_offset, self)
    subfile_strip_data_offset = subfile_offsets_data_offset + strip_count * tags[Tag::Name::StripOffsets].type.bytesize
    tags[Tag::Name::StripByteCounts] = Entry.new(Tag::Name::StripByteCounts, Tag::Type::Long, strip_count, subfile_strip_data_offset, self)

    tags
  end

  def initialize(@file_path : String)
    @file_io = ::File.open @file_path, "rb"
    @header = Header.new read_buffer byte_size: 8

    # Baseline TIFF only has one subfile
    # Support for full TIFF specification can be added later
    @subfile = SubFile.new extract_tags from: @file_io
  end

  def initialize(@tensor : Tensor(UInt8, CPU(UInt8)), @file_path : String)
    @file_io = ::File.open @file_path, "wb"
    @header = Header.new

    @subfile = SubFile.new extract_tags from: @tensor.not_nil!
  end

  delegate endian_format, offset, to: @header

  def encode(int_data : Int, bytes : Bytes)
    raise "int_data size does not match byte size" unless bytes.size == sizeof(typeof(int_data))
    endian_format.encode int_data, bytes
  end

  macro generate_buffer_extraction_defs(byte_size)
    {% byte_bits = byte_size.id.to_i * 8 %}

    def read_buffer(byte_size)
      Bytes.new(byte_size).tap {|b| @file_io.read_fully(b) }
    end

    def get_bytes(value : UInt{{byte_bits}})
      Bytes.new({{byte_size}}).tap do |buffer|
        endian_format.encode(value, buffer)
      end
    end

    def encode_{{byte_size}}_bytes(value : UInt{{byte_bits}})
      endian_format.encode endian_format.to_bytes(value), @file_io
    end

    def encode_{{byte_size}}_bytes(value : UInt{{byte_bits}}, seek_to : Int)
      @file_io.seek seek_to, IO::Seek::Set
      encode_{{byte_size}}_bytes(value)
    end

    def encode_{{byte_size}}_bytes(values : Array(UInt{{byte_bits}}), seek_to : Int)
      @file_io.seek seek_to, IO::Seek::Set
      values.each do |value|
        encode_{{byte_size}}_bytes(value)
      end
    end

    def decode_{{byte_size}}_bytes
      endian_format.decode UInt{{byte_bits}}, read_buffer({{byte_size}})
    end

    def decode_{{byte_size}}_bytes(*, times : Int)
      Array(UInt{{byte_bits}}).new(times) do
        decode_{{byte_size}}_bytes
      end
    end

    def decode_{{byte_size}}_bytes(*, seek_to : Int)
      @file_io.seek seek_to, IO::Seek::Set
      decode_{{byte_size}}_bytes
    end

    def decode_{{byte_size}}_bytes(seek_to, times)
      @file_io.seek seek_to, IO::Seek::Set
      Array(UInt{{byte_bits}}).new(times) do
        decode_{{byte_size}}_bytes
      end
    end

    def decode_{{byte_size}}_bytes(bytes : Slice(UInt8), start_at = 0)
      endian_format.decode UInt{{byte_bits}}, bytes[start_at...start_at + {{byte_size}}]
    end
  end

  {% for byte_size in [1, 2, 4, 8] %}
    generate_buffer_extraction_defs {{byte_size}}
  {% end %}

  def write(buffer : Bytes)
    @file_io.write buffer
  end

  def get_printable(bytes)
    if bytes.size <= 8
      bytes.map(&.to_s(16).rjust(2, '0')).join(' ')
    else
      bytes[0..2].map(&.to_s(16).rjust(2, '0')).join(' ') + "..." + bytes[-3..-1].map(&.to_s(16).rjust(2, '0')).join(' ')
    end
  end

  # TODO: ability to write in configured chunk sizes
  # Writing large file should be done in steps to avoid high memory usage
  # Good step sizes can vary from 4KB to 1MB depending on the system
  def get_bytes
    header_offset = 0_u32
    header_bytes = @header.get_bytes
    Log.trace &.emit("Header bytes to be written:", size: header_bytes.size, bytes: get_printable(header_bytes), offset: header_offset)

    tags_offset = header_offset + header_bytes.size
    tag_bytes = @subfile.not_nil!.get_directory_entry_bytes(self)
    Log.trace &.emit("Tags bytes to be written", size: tag_bytes.size, bytes: get_printable(tag_bytes), offset: tags_offset)

    resolution_offset = tags_offset + tag_bytes.size
    resolution_bytes = @subfile.not_nil!.get_resolution_bytes(self)
    Log.trace &.emit("Resolution bytes to be written", size: resolution_bytes.size, bytes: get_printable(resolution_bytes), offset: resolution_offset)

    all_strip_bytes = @subfile.not_nil!.get_all_strip_bytes(self)

    strip_offsets = [] of UInt32
    strip_bytes_counts = [] of UInt32
    current_offset = resolution_offset + resolution_bytes.size

    all_strip_bytes.each_with_index do |strip_bytes, index|
      strip_offsets << current_offset
      strip_bytes_counts << strip_bytes.size.to_u32
      Log.trace &.emit("Strip #{index} bytes to be written", size: strip_bytes.size, bytes: get_printable(strip_bytes), offset: current_offset)

      current_offset += strip_bytes.size
    end
  end

  def to_tensors
    @subfile.not_nil!.to_tensor(self)
  end
end
