module Format::Tiff::Tag
  enum Name : UInt16
    # This is not used currently, but reserved for future use
    NewSubfileType = 254_u16
    ImageWidth = 256_u16
    ImageLength = 257_u16
    BitsPerSample = 258_u16
    Compression = 259_u16
    PhotometricInterpretation = 262_u16
    ImageDescription = 270_u16
    StripOffsets = 273_u16
    Orientation = 274_u16
    SamplesPerPixel = 277_u16
    RowsPerStrip = 278_u16
    StripByteCounts = 279_u16
    XResolution = 282_u16
    YResolution = 283_u16
    ResolutionUnit = 296_u16

    def to_json_object_key
      to_s.underscore
    end

    def type : Type
      case self
      when ImageWidth, ImageLength, StripOffsets, RowsPerStrip, StripByteCounts, NewSubfileType
        Type::Long
      when BitsPerSample, Compression, Orientation, SamplesPerPixel, ResolutionUnit, PhotometricInterpretation
        Type::Short
      when ImageDescription
        Type::Ascii
      when XResolution, YResolution
        Type::Rational
      else
        raise "Unknown Tag Name"
      end
    end
  end

  DIRECTORY_ENTRIES_COUNT = 15_u16

  enum Type : UInt16
    Byte = 1_u16     # 1 byte
    Ascii = 2_u16    # 1 byte
    Short = 3_u16    # 2 bytes
    Long = 4_u16     # 4 bytes
    Rational = 5_u16 # 8 bytes

    def bytesize
      case self
      when Byte     then 1_u16
      when Ascii    then 1_u16
      when Short    then 2_u16
      when Long     then 4_u16
      when Rational then 8_u16
      else
        raise "Unknown Tag Type"
      end
    end
  end
end
