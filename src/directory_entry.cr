class Format::Tiff::File::SubFile
  struct DirectoryEntry
    SIZE = 12_u32

    include JSON::Serializable

    Log = SubFile::Log.for("directory_entry")

    getter tag : Tag::Name
    getter tag_code : UInt16
    getter count : UInt32
    getter type : Tag::Type
    getter offset : UInt32?
    # getter value_or_offset : UInt32

    @[JSON::Field(ignore: true)]
    getter value_bytes = Bytes.empty

    @[JSON::Field(ignore: true)]
    @file_context : Tiff::File::Context

    def initialize(@tag, @count, @value_bytes, @offset, @file_context : Tiff::File::Context)
      @tag_code = @tag.value
      @type = @tag.type
    end

    def initialize(@file_context : Tiff::File::Context)
      entry_bytes = @file_context.read_bytes(DirectoryEntry::SIZE)

      Log.trace &.emit("Processing tag", entry_bytes: Format.get_printable(entry_bytes, size_threshold_for_compaction: 12))
      @tag = Tag::Name.new @file_context.read_u16_value from: entry_bytes, start_offset: 0

      Log.trace &.emit("Processing tag", tag: @tag.value.to_u32)
      @tag_code = @tag.value
      @type = Tag::Type.new @file_context.read_u16_value from: entry_bytes, start_offset: 2
      @count = @file_context.read_u32_value from: entry_bytes, start_offset: 4

      if @type.bytesize * @count > 4
        @offset = @file_context.read_u32_value from: entry_bytes, start_offset: 8
      else
        @value_bytes = entry_bytes[8..11]
      end
    end

    # REASON
    # Resolves offsets after initialization because during initialization we are running through all tags sequentially.
    # Resolving offsets requires seeking to different parts of the file which would disrupt the sequential reading and degrade performance.
    def resolve_offset
      unless (offset = @offset).nil?
        @value_bytes = @file_context.read_bytes(@type.bytesize * @count, start_offset: offset)
      end
      self
    end

    def value
      offset = @offset

      value_array = if offset.nil?
        total_bytes_to_read = @value_bytes.size
        unless total_bytes_to_read == 4
          raise "Value must be stored in the 4 bytes(8th to 11th) of the directory entry."
        end

        bytes_occupied_by_one_value = total_bytes_to_read // @count

        case bytes_occupied_by_one_value
        when 1
          @file_context.read_u8_values(from: @value_bytes, count: @count)
        when 2
          @file_context.read_u16_values(from: @value_bytes, count: @count)
        when 4
          @file_context.read_u32_values(from: @value_bytes, count: @count)
        else
          raise "Unsupported byte size per value: #{bytes_occupied_by_one_value}"
        end
      else
        case @type
        when Tag::Type::Byte
          @file_context.read_u8_values(from: @value_bytes, count: @count)
        when Tag::Type::Short
          @file_context.read_u16_values(from: @value_bytes, count: @count)
        when Tag::Type::Long
          @file_context.read_u32_values(from: @value_bytes, count: @count)
        when Tag::Type::Rational
          rationals = @file_context.read_u64_values(from: @value_bytes, count: @count)
          rationals.map do |rational|
            numerator = (rational >> 32) & 0xFFFFFFFF_u32
            denominator = rational & 0xFFFFFFFF_u32
            [numerator, denominator]
          end
        else
          raise "Tag value extraction not implemented for type #{@type}"
        end
      end

      value_array.size == 1 ? value_array[0] : value_array
    end

    def get_bytes
      offset = @offset
      Bytes.new(12).tap do |buffer|
        @file_context.endian_format.encode(@tag_code, buffer[0..1])
        @file_context.endian_format.encode(@type.value, buffer[2..3])
        @file_context.endian_format.encode(@count, buffer[4..7])
        # @file_context.endian_format.encode(@value_or_offset, buffer[8..11])

        if offset.nil?
          @value_bytes.copy_to buffer[8..11]
        else
          @file_context.endian_format.encode(offset, buffer[8..11])
        end
      end
    end

    def encode(buffer, start_offset = 0)
      offset = @offset

      @file_context.endian_format.encode(@tag_code, buffer[start_offset..(start_offset + 1)])
      @file_context.endian_format.encode(@type.value, buffer[(start_offset + 2)..(start_offset + 3)])
      @file_context.endian_format.encode(@count, buffer[(start_offset + 4)..(start_offset + 7)])
      # @file_context.endian_format.encode(@value_or_offset, buffer[8..11])

      if offset.nil?
        @value_bytes.copy_to buffer[(start_offset + 8)..(start_offset + 11)]
      else
        @file_context.endian_format.encode(offset, buffer[(start_offset + 8)..(start_offset + 11)])
      end
    end

    def get_resolution_bytes
      unless @tag == Tag::Name::XResolution || @tag == Tag::Name::YResolution
        raise "Tag is not XResolution or YResolution type"
      end

      Bytes.new(8).tap do |bytes|
        @file_context.endian_format.encode(118_u32, bytes[0..3])
        @file_context.endian_format.encode(1_u32, bytes[4..7])
      end
    end
  end
end
