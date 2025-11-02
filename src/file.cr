# TODO: Nicely add comments and documentation in entire repo
class Format::Tiff::File
  include JSON::Serializable

  Log = ::Log.for("tiff-file", level: :trace)

  alias Entry = Format::Tiff::File::SubFile::DirectoryEntry
  ROWS_PER_STRIP = 32_u32

  @file_path : String
  @header : Header
  @subfile : SubFile

  @[JSON::Field(ignore: true)]
  @context : Context

  def parse_header
    header_bytes = @context.read_bytes 8
    @context.endian_format = Tiff.get_endianness header_bytes[0...2]

    tiff_identifier = @context.endian_format.decode UInt16, header_bytes[2...4]
    raise "Not a TIFF file" unless tiff_identifier == TIFF_IDENTIFICATION_CODE

    offset = @context.endian_format.decode UInt32, header_bytes[4...8]

    {
      endian_format: @context.endian_format,
      tiff_identifier: tiff_identifier,
      offset: offset
    }
  end

  def initialize(@file_path : String)
    @context = Context.new(::File.open @file_path, "rb")
    @header = Header.new **parse_header

    # Baseline TIFF only has one subfile
    # Support for full TIFF specification can be added later
    @subfile = SubFile.new(offset, @context)
  end

  def initialize(tensor : Tensor(UInt8, CPU(UInt8)), @file_path : String)
    @context = Context.new(tensor, ::File.open @file_path, "wb")
    @header = Header.new(@context.endian_format, TIFF_IDENTIFICATION_CODE)

    @subfile = SubFile.new(@context)
  end

  delegate offset, to: @header

  def encode(int_data : Int, bytes : Bytes)
    raise "int_data size does not match byte size" unless bytes.size == sizeof(typeof(int_data))
    endian_format.encode int_data, bytes
  end

  def get_printable(bytes)
    if bytes.size <= 8
      bytes.map(&.to_s(16).rjust(2, '0')).join(' ')
    else
      bytes[0..2].map(&.to_s(16).rjust(2, '0')).join(' ') + "..." + bytes[-3..-1].map(&.to_s(16).rjust(2, '0')).join(' ')
    end
  end

  # TODO: ability to write files as a series of buffers with pre-configured size
  # Writing large file should be done in steps to avoid high memory usage.
  # A good buffer size configuration can vary from 4KB to 1MB depending on the system.
  def get_bytes
    header_offset = 0_u32
    header_bytes = @header.get_bytes
    Log.trace &.emit("Header bytes to be written:", size: header_bytes.size, bytes: get_printable(header_bytes), offset: header_offset)

    tags_offset = header_offset + header_bytes.size
    tag_bytes = @subfile.get_directory_entry_bytes
    Log.trace &.emit("Tags bytes to be written", size: tag_bytes.size, bytes: get_printable(tag_bytes), offset: tags_offset)

    resolution_offset = tags_offset + tag_bytes.size
    resolution_bytes = @subfile.get_resolution_bytes
    Log.trace &.emit("Resolution bytes to be written", size: resolution_bytes.size, bytes: get_printable(resolution_bytes), offset: resolution_offset)

    all_strip_bytes = @subfile.get_all_strip_bytes

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
    @subfile.to_tensor
  end
end
