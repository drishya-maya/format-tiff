# TODO: Nicely add comments and documentation in entire repo
class Format::Tiff::File
  include JSON::Serializable

  Log = ::Log.for self

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
    file_io = ::File.open(@file_path, "r")
    Log.trace &.emit("Opened file to read.", path: @file_path, permissions: file_io.info.permissions.to_s)

    @context = Context.new(file_io)
    @header = Header.new **parse_header

    # Baseline TIFF only has one subfile
    # Support for full TIFF specification can be added later
    @subfile = SubFile.new(offset, @context)
  end

  def initialize(tensor : Tensor(UInt8, CPU(UInt8)), @file_path : String)
    file_io = ::File.open(@file_path, "w")
    Log.trace &.emit("Opened file to write.", path: @file_path, permissions: file_io.info.permissions.to_s)

    @context = Context.new(tensor, file_io)
    @header = Header.new(@context.endian_format, TIFF_IDENTIFICATION_CODE)

    @subfile = SubFile.new(@context)
    @header.offset = @subfile.image_file_directory_offset
  end

  delegate offset, to: @header

  # TODO: ability to write files as a series of buffers with pre-configured size
  # Writing large file should be done in steps to avoid high memory usage.
  # A good buffer size configuration can vary from 4KB to 1MB depending on the system.
  def write
    Log.trace &.emit "Writing TIFF file.", path: @file_path

    @header.write(@context)
    @subfile.write

    @context.save
  end

  def to_tensors
    @subfile.to_tensor
  end
end
