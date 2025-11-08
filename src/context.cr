class Format::Tiff::File
  class Context
    Log = File::Log.for("context")

    property endian_format : IO::ByteFormat = IO::ByteFormat::LittleEndian
    property file_io : ::File?
    property tensor : Tensor(UInt8, CPU(UInt8))?

    def initialize(@file_io : ::File)
    end

    def initialize(@tensor : Tensor(UInt8, CPU(UInt8)))
    end

    def initialize(@endian_format : IO::ByteFormat, @file_io : ::File, @tensor : Tensor(UInt8, CPU(UInt8)))
    end

    def finalize
      @file_io.not_nil!.close unless @file_io.not_nil!.closed?
    end

    def tensor?
      !@tensor.nil?
    end

    def current_offset
      @file_io.not_nil!.pos
    end

    # Read *count* `Bytes` from the tiff file.
    def read_bytes(count)
      Bytes.new(count).tap {|b| @file_io.not_nil!.read_fully(b) }
    end

    def read_bytes(count, *, start_offset : Int)
      @file_io.not_nil!.seek start_offset, IO::Seek::Set
      Bytes.new(count).tap {|b| @file_io.not_nil!.read_fully(b) }
    end

    macro generate_buffer_extraction_defs(bytesize)
      {% byte_bits = bytesize.id.to_i * 8 %}

      # Convert *value* to `Bytes`.
      #
      # Returns the `Bytes` generated from *value*.
      def get_bytes(value : UInt{{byte_bits}})
        Bytes.new({{bytesize}}).tap do |bytes|
          endian_format.encode(value, bytes)
        end
      end

      def read_u{{byte_bits}}_value
        endian_format.decode UInt{{byte_bits}}, read_bytes({{bytesize}})
      end

      def read_u{{byte_bits}}_values(count : Int)
        Array(UInt{{byte_bits}}).new(count) do
          read_u{{byte_bits}}_value
        end
      end

      def read_u{{byte_bits}}_value(*, start_offset : Int)
        @file_io.not_nil!.seek start_offset, IO::Seek::Set
        read_u{{byte_bits}}_value
      end

      def read_u{{byte_bits}}_value(from : Bytes, start_offset = 0) : UInt{{byte_bits}}
        bytes = from
        endian_format.decode UInt{{byte_bits}}, bytes[start_offset...start_offset + {{bytesize}}]
      end

      def read_u{{byte_bits}}_values(from : Bytes, *, count, start_offset = 0) : Array(UInt{{byte_bits}})
        bytes = from
        Array(UInt{{byte_bits}}).new(count) do |i|
          read_u{{byte_bits}}_value(from, start_offset + i * {{bytesize}})
        end
      end
    end

    {% for bytesize in [1, 2, 4, 8] %}
      generate_buffer_extraction_defs {{bytesize}}
    {% end %}

    def write(bytes)
      @file_io.not_nil!.write bytes
    end

    def save
      @file_io.not_nil!.flush
    end

    def write(bytes, start_offset = 0)
      @file_io.not_nil!.seek start_offset, IO::Seek::Set
      @file_io.not_nil!.write bytes
    end
  end
end
