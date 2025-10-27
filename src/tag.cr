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
  end

  enum Type : UInt16
    BYTE = 1_u16
    ASCII = 2_u16
    SHORT = 3_u16
    LONG = 4_u16
    RATIONAL = 5_u16
  end
end
