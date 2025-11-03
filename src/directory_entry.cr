class Format::Tiff::File::SubFile
  struct DirectoryEntry
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
    @context : Tiff::File::Context

    # @[JSON::Field(ignore: true)]
    # @entry_bytes : Bytes

    def initialize(@tag, @type, @count, value_or_offset, @context : Tiff::File::Context)
      @tag_code = @tag.value

      if @type.bytesize * @count > 4
        @offset = value_or_offset
      else
        fitting_bytes = @context.get_bytes(value_or_offset)

        @value_bytes = Bytes.new(4, 0)
        fitting_bytes.copy_to @value_bytes
      end
    end

    def initialize(@context : Tiff::File::Context)
      entry_bytes = @context.read_bytes(12)

      Log.trace &.emit("Processing tag", entry_bytes: Format.get_printable(entry_bytes, size_threshold_for_compaction: 12))
      @tag = Tag::Name.new @context.read_u16_value from: entry_bytes, start_offset: 0

      Log.trace &.emit("Processing tag", tag: @tag.value.to_u32)
      @tag_code = @tag.value
      @type = Tag::Type.new @context.read_u16_value from: entry_bytes, start_offset: 2
      @count = @context.read_u32_value from: entry_bytes, start_offset: 4
      # @value_or_offset = @context.read_u32_value from: @entry_bytes, start_offset: 8

      if @type.bytesize * @count > 4
        @offset = @context.read_u32_value from: entry_bytes, start_offset: 8
      else
        @value_bytes = entry_bytes[8..11]
      end
    end

    # REASON
    # Resolves offsets after initialization because during initialization we are running through all tags sequentially.
    # Resolving offsets requires seeking to different parts of the file which would disrupt the sequential reading and degrade performance.
    def resolve_offset
      unless (offset = @offset).nil?
        @value_bytes = @context.read_bytes(@type.bytesize * @count, start_offset: offset)
      end
      self
    end

    # def value
    #   case @tag
    #   when Tag::Name::ImageWidth, Tag::Name::ImageLength
    #     @context.read_u32_value(from: @value_bytes, start_offset: 0)
    #   when Tag::Name::StripOffsets, Tag::Name::StripByteCounts
    #     @context.read_u32_values(from: @value_bytes, count: @count)
    #   when Tag::Name::XResolution, Tag::Name::YResolution
    #     @context.read_u32_values(count: 2) # numerator
    #   else
    #     raise "Tag value extraction not implemented for #{@tag}"
    #   end
    # end

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
          @context.read_u8_values(from: @value_bytes, count: @count)
        when 2
          @context.read_u16_values(from: @value_bytes, count: @count)
        when 4
          @context.read_u32_values(from: @value_bytes, count: @count)
        else
          raise "Unsupported byte size per value: #{bytes_occupied_by_one_value}"
        end
      else
        case @type
        when Tag::Type::Byte
          @context.read_u8_values(from: @value_bytes, count: @count)
        when Tag::Type::Short
          @context.read_u16_values(from: @value_bytes, count: @count)
        when Tag::Type::Long
          @context.read_u32_values(from: @value_bytes, count: @count)
        when Tag::Type::Rational
          rationals = @context.read_u64_values(from: @value_bytes, count: @count)
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

    # def read_resolution_bytes
    #   unless @tag == Tag::Name::XResolution || @tag == Tag::Name::YResolution
    #     raise "Tag is not XResolution or YResolution type"
    #   end

    #   @context.read_bytes @type.bytesize * @count, start_offset: @offset.not_nil!
    # end

    # def read_long_fraction
    #   unless {Tag::Name::XResolution, Tag::Name::YResolution}.includes? @tag
    #     raise "Tag is not a resolution type"
    #   end

    #   @context.file_io.seek @value_or_offset, IO::Seek::Set
    #   numerator = @context.read_u32_value
    #   denominator = @context.read_u32_value

    #   numerator.to_f64 / denominator.to_f64
    # end

    # def write_long_fraction(numerator, denominator, writer)
    #   unless {Tag::Name::XResolution, Tag::Name::YResolution}.includes? @tag
    #     raise "Tag is not a resolution type"
    #   end

    #   writer.encode_4_bytes([numerator, denominator], seek_to: @value_or_offset) # value_or_offset
    # end

    # def read_longs
    #   unless {Tag::Name::StripOffsets, Tag::Name::StripByteCounts}.includes? @tag
    #     raise "Tag is not a strip offsets type"
    #   end

    #   if @count <= 1
    #     # values are stored directly in the value_or_offset field
    #     [@value_or_offset]
    #   else
    #     # values are stored at the offset location
    #     Log.trace &.emit("Reading long values", permissions: @context.file_io.info.permissions.to_s)

    #     @context.file_io.seek @value_or_offset, IO::Seek::Set
    #     Array(UInt32).new(@count) do
    #       @context.read_u32_value
    #     end
    #   end
    # end

    # def write_longs(longs : Array(UInt32), writer)
    #     writer.encode_4_bytes longs, seek_to: @value_or_offset
    # end

    def get_bytes
      offset = @offset
      Bytes.new(12).tap do |buffer|
        @context.endian_format.encode(@tag_code, buffer[0..1])
        @context.endian_format.encode(@type.value, buffer[2..3])
        @context.endian_format.encode(@count, buffer[4..7])
        # @context.endian_format.encode(@value_or_offset, buffer[8..11])

        if offset.nil?
          @value_bytes.copy_to buffer[8..11]
        else
          @context.endian_format.encode(offset, buffer[8..11])
        end
      end
    end

    def get_resolution_bytes
      unless @tag == Tag::Name::XResolution || @tag == Tag::Name::YResolution
        raise "Tag is not XResolution or YResolution type"
      end

      Bytes.new(8).tap do |bytes|
        @context.endian_format.encode(118_u32, bytes[0..3])
        @context.endian_format.encode(1_u32, bytes[4..7])
      end
    end
  end
end
