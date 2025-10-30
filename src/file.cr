class Format::Tiff::File
  include JSON::Serializable

  alias Entry = Format::Tiff::File::SubFile::DirectoryEntry
  ROWS_PER_STRIP = 32_u32

  @[JSON::Field(ignore: true)]
  getter file_io : ::File

  getter file_path : String
  @header : Header
  getter subfile : SubFile?

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

    image_height = tensor.shape[0].to_u32
    image_width = tensor.shape[1_u32].to_u32
    tags[Tag::Name::SamplesPerPixel] = Entry.new(Tag::Name::SamplesPerPixel, Tag::Type::Short, 1_u32, 1_u32, self)
    tags[Tag::Name::BitsPerSample] = Entry.new(Tag::Name::BitsPerSample, Tag::Type::Short, 1_u32, 8, self)
    tags[Tag::Name::ImageWidth] = Entry.new(Tag::Name::ImageWidth, Tag::Type::Long, 1_u32, image_width, self)
    tags[Tag::Name::ImageLength] = Entry.new(Tag::Name::ImageLength, Tag::Type::Long, 1_u32, image_height, self)

    subfile_end_offset = MAX_TAG_COUNT * DIRECTORY_ENTRY_SIZE + HEADER_SIZE + 1_u32
    x_resolution_offset = subfile_end_offset
    y_resolution_offset = x_resolution_offset + 8
    tags[Tag::Name::XResolution] = Entry.new(Tag::Name::XResolution, Tag::Type::Rational, 1_u32, subfile_end_offset, self)
    tags[Tag::Name::YResolution] = Entry.new(Tag::Name::YResolution, Tag::Type::Rational, 1_u32, y_resolution_offset, self)
    tags[Tag::Name::ResolutionUnit] = Entry.new(Tag::Name::ResolutionUnit, Tag::Type::Short, 1_u32, 3, self)

    subfile_data_offset = subfile_end_offset + MAX_TAG_COUNT * MAX_TAG_TYPE_SIZE + 1_u32
    total_strip_count = image_height // ROWS_PER_STRIP + 1_u32
    bytes_per_strip = image_width * ROWS_PER_STRIP
    tags[Tag::Name::Compression] = Entry.new(Tag::Name::Compression, Tag::Type::Short, 1_u32, 1_u32, self)
    tags[Tag::Name::Orientation] = Entry.new(Tag::Name::Orientation, Tag::Type::Short, 1_u32, 1_u32, self)
    tags[Tag::Name::RowsPerStrip] = Entry.new(Tag::Name::RowsPerStrip, Tag::Type::Long, 1_u32, ROWS_PER_STRIP, self)
    tags[Tag::Name::StripOffsets] = Entry.new(Tag::Name::StripOffsets, Tag::Type::Long, total_strip_count, subfile_data_offset, self)
    tags[Tag::Name::StripByteCounts] = Entry.new(Tag::Name::StripByteCounts, Tag::Type::Long, total_strip_count, bytes_per_strip, self)

    tags
  end

  def initialize(@file_path : String)
    @file_io = ::File.open @file_path, "rb"
    @header = Header.new read_buffer byte_size: 8

    # Baseline TIFF only has one subfile
    # Support for full TIFF specification can be added later
    @subfile = SubFile.new extract_tags from: @file_io
  end

  def initialize(tensor : Tensor(UInt8, CPU(UInt8)), @file_path : String)
    @file_io = ::File.open @file_path, "wb"
    @header = Header.new

    @subfile = SubFile.new extract_tags from: tensor
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

  def write
    @header.write(self)
  end

  def to_tensors
    @subfile.not_nil!.to_tensor(self)
  end
end
