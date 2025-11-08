# PERFORMANCE: Optimize buffer creation. create large buffer and write into it instead of concatenating smaller buffers.

class Format::Tiff::File
  class SubFile
    include JSON::Serializable

    Log = File::Log.for("subfile")

    @[JSON::Field(ignore: true)]
    @file_context : Tiff::File::Context

    @directory_entries : Hash(Tag::Name, Entry)
    @directory_entries_count : UInt16
    @strip_offsets : Array(UInt32)
    @strip_bytes_counts : Array(UInt32)
    @width : UInt32

    @[JSON::Field(ignore: true)]
    @strips_bytes : Array(Bytes)

    def initialize(@file_context : Tiff::File::Context)
      @directory_entries_count = Tag::DIRECTORY_ENTRIES_COUNT

      @directory_entries,
      @strip_offsets,
      @strip_bytes_counts,
      @strips_bytes,
      @width = construct_subfile
    end

    def initialize(offset : UInt32, @file_context : Tiff::File::Context)
      @directory_entries_count = @file_context.read_u16_value start_offset: offset
      @directory_entries = read_directory_entries

      @strip_offsets = @directory_entries[Tag::Name::StripOffsets].value.as Array(UInt32)
      @strip_bytes_counts = @directory_entries[Tag::Name::StripByteCounts].value.as Array(UInt32)
      @strips_bytes = read_strip_bytes

      @width = @directory_entries[Tag::Name::ImageWidth].value.as UInt32
    end

    def read_directory_entries
      Array(Entry).new(@directory_entries_count) {
        Entry.new @file_context
      }.map {|entry|
        {entry.tag, entry.resolve_offset}
      }.to_h
    end

    def get_directory_entry_tuple(tag : Tag::Name, count : UInt32, value : Array(UInt32), offset)
      if [Tag::Name::XResolution, Tag::Name::YResolution].includes? tag
        value_bytes = value.as(Array(UInt32)).reduce(Bytes.empty) {|acc, v| acc + @file_context.get_bytes(v) }
      end

      if [Tag::Name::StripOffsets, Tag::Name::StripByteCounts].includes? tag
        value_bytesize = tag.type.bytesize
        value_bytes = Bytes.new(count * value_bytesize).tap do |bytes|
          value.as(Array(UInt32)).each_with_index do |v, i|
            @file_context.endian_format.encode v, bytes[i * value_bytesize...(i+1) * value_bytesize]
          end
        end
      end

      {tag, Entry.new(tag, count, value_bytes.not_nil!, offset, @file_context)}
    end

    def get_directory_entry_tuple(tag : Tag::Name, count : UInt32, value : Int, offset)
      value_bytes = @file_context.get_bytes(value.to_u32)
      {tag, Entry.new(tag, count, value_bytes.not_nil!, offset, @file_context)}
    end

    def construct_subfile
      tensor = @file_context.tensor.not_nil!
      raise "Invalid tensor shape" unless tensor.shape.size == 2

      directory_entries_tuples = Array(Tuple(Tag::Name, Entry)).new(Tag::DIRECTORY_ENTRIES_COUNT)

      directory_entries_tuples << get_directory_entry_tuple(
                                    Tag::Name::NewSubfileType,
                                    count: 1_u32,
                                    value: 0_u32,
                                    offset: nil
                                  )
      directory_entries_tuples << get_directory_entry_tuple(
                                    Tag::Name::PhotometricInterpretation,
                                    count: 1_u32,
                                    value: 1_u32,
                                    offset: nil
                                  )
      directory_entries_tuples << get_directory_entry_tuple(
                                    Tag::Name::ImageDescription,
                                    count: 0_u32,
                                    value: 0_u32,
                                    offset: nil
                                  )

      rows_per_strip = Tiff::File::ROWS_PER_STRIP
      directory_entries_tuples << get_directory_entry_tuple(
                                    Tag::Name::RowsPerStrip,
                                    count: 1_u32,
                                    value: rows_per_strip,
                                    offset: nil
                                  )

      width = tensor.shape[1].to_u32
      height = tensor.shape[0].to_u32
      directory_entries_tuples << get_directory_entry_tuple(
                                    Tag::Name::ImageWidth,
                                    count: 1_u32,
                                    value: width,
                                    offset: nil
                                  )
      directory_entries_tuples << get_directory_entry_tuple(
                                    Tag::Name::ImageLength,
                                    count: 1_u32,
                                    value: height,
                                    offset: nil
                                  )

      x_resolution_offset = current_offset = HEADER_SIZE + 1_u32
      directory_entries_tuples << get_directory_entry_tuple(
                                    Tag::Name::XResolution,
                                    count: 1_u32,
                                    value: [118_u32, 1_u32],
                                    offset: x_resolution_offset
                                  )

      y_resolution_offset = current_offset = x_resolution_offset + Tag::Name::XResolution.type.bytesize
      directory_entries_tuples << get_directory_entry_tuple(
                                    Tag::Name::YResolution,
                                    count: 1_u32,
                                    value: [118_u32, 1_u32],
                                    offset: y_resolution_offset
                                  )

      directory_entries_tuples << get_directory_entry_tuple(
                                    Tag::Name::ResolutionUnit,
                                    count: 1_u32,
                                    value: 3_u32,
                                    offset: nil
                                  )

      directory_entries_tuples << get_directory_entry_tuple(
                                    Tag::Name::SamplesPerPixel,
                                    count: 1_u32,
                                    value: 1_u32,
                                    offset: nil
                                  )

      directory_entries_tuples << get_directory_entry_tuple(
                                    Tag::Name::BitsPerSample,
                                    count: 1_u32,
                                    value: 8_u32,
                                    offset: nil
                                  )
      directory_entries_tuples << get_directory_entry_tuple(
                                    Tag::Name::Compression,
                                    count: 1_u32,
                                    value: 1_u32,
                                    offset: nil
                                  )
      directory_entries_tuples << get_directory_entry_tuple(
                                    Tag::Name::Orientation,
                                    count: 1_u32,
                                    value: 1_u32,
                                    offset: nil
                                  )

      strips_count = (height / rows_per_strip).ceil.to_u32
      all_strip_bytes = Array(Bytes).new(strips_count)
      strip_offsets = Array(UInt32).new(strips_count)
      strip_byte_counts = Array(UInt32).new(strips_count)
      strips_count.times do |index|
        strip_offset = current_offset
        strip_offsets << strip_offset

        strip_bytes = get_strip_bytes(index)
        strip_byte_counts << strip_bytes.size.to_u32
        all_strip_bytes << strip_bytes

        current_offset = strip_offset + strip_bytes.size
      end

      strip_offsets_offset = current_offset
      directory_entries_tuples << get_directory_entry_tuple(
                                    Tag::Name::StripOffsets,
                                    count: strips_count,
                                    value: strip_offsets,
                                    offset: strip_offsets_offset
                                  )

      strip_byte_counts_offset = current_offset = strip_offsets_offset + strips_count * Tag::Name::StripOffsets.type.bytesize
      directory_entries_tuples << get_directory_entry_tuple(
                                    Tag::Name::StripByteCounts,
                                    count: strips_count,
                                    value: strip_byte_counts,
                                    offset: strip_byte_counts_offset
                                  )

      # image_file_directory_offset = current_offset = strip_byte_counts_offset + strips_count * Tag::Name::StripByteCounts.type.bytesize

      # # TODO get DIRECTORY_ENTRIES_COUNT using a macro to get enum size
      # directory_entries_count_bytes = get_bytes(Tiff::File::Tag::DIRECTORY_ENTRIES_COUNT)
      # # current_offset = image_file_directory_offset + directory_entries_count_bytes.size

      # directory_entries_bytes = Bytes.new(Tiff::File::Tag::DIRECTORY_ENTRIES_COUNT * DirectoryEntry::SIZE)
      # @directory_entries.values.sort_by(&.tag_code).each_with_index do |entry, i|
      #   entry.encode(directory_entries_bytes[i * DirectoryEntry::SIZE...(i + 1) * DirectoryEntry::SIZE])
      #   # current_offset += DirectoryEntry::SIZE
      # end

      {directory_entries_tuples.to_h, strip_offsets, strip_byte_counts, all_strip_bytes, width}
    end

    def read_strip_bytes
      @strip_offsets.map_with_index do |offset, index|
        @file_context.read_bytes(@strip_bytes_counts[index], start_offset: offset)
      end
    end

    def read_strips
      @strips_bytes.map do |strip_bytes|
        rows_in_strip = strip_bytes.size // @width
        Array(Array(UInt8)).new(rows_in_strip) do |row_index|
          start_offset = row_index * @width
          @file_context.read_u8_values strip_bytes[start_offset...(start_offset + @width)], count: @width
        end
      end
    end

    def get_row_bytes(row : Tensor(UInt8, CPU(UInt8)))
      Bytes.new(row.size).tap do |row_bytes|
        row.each_with_index do |value, i|
          @file_context.endian_format.encode value, row_bytes[i..i]
        end
      end
    end

    # TODO: Learn Tensor API and use performant functions for tensor iterations
    def get_strip_bytes(strip_index : Int)
      tensor = @file_context.tensor.not_nil!

      strip_tensor = tensor[(strip_index * ROWS_PER_STRIP)...((strip_index+1) * ROWS_PER_STRIP)]

      bytes = Bytes.empty
      strip_tensor.each_axis(0) do |row|
        bytes += get_row_bytes(row)
      end

      bytes
    end

    def to_rows
      read_strips.flat_map &.itself
    end

    # PERFORMANCE: can performance be improved by directly creating tensor from file IO instead of array?
    def to_tensor
      to_rows.to_tensor
    end

    # Write order:
    # header
    # subfile1 -> resolutions -> strips -> strip offsets -> strip byte counts -> image file directory
    # subfile2 -> resolutions -> strips -> strip offsets -> strip byte counts -> image file directory
    # subfile3 -> resolutions -> strips -> strip offsets -> strip byte counts -> image file directory
    # ...
    def write

    end
  end
end
