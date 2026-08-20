using System.Buffers.Binary;
using System.Text;

namespace InfDir.FontView;

internal static class FontPreparation
{
    public static void SelfTest()
    {
        byte[] payload = "\0\x01\0\0Inf-Dir-font-test"u8.ToArray();
        string temp = Path.Combine(Path.GetTempPath(), "Inf-Dir", "font-view-self-test", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(temp);
        try
        {
            string dfont = Path.Combine(temp, "test.dfont");
            string sfnt = Path.Combine(temp, "test.ttf");
            File.WriteAllBytes(dfont, BuildTestDfont(payload));
            ExtractDfont(dfont, sfnt);
            if (!File.ReadAllBytes(sfnt).SequenceEqual(payload))
            {
                throw new InvalidDataException("DFONT self-test extracted different bytes.");
            }
        }
        finally
        {
            Directory.Delete(temp, recursive: true);
        }
    }

    public static void ExtractDfont(string source, string output)
    {
        byte[] file = File.ReadAllBytes(source);
        if (file.Length < 16)
        {
            throw new InvalidDataException("DFONT resource fork header is incomplete.");
        }

        int dataOffset = ReadOffset(file, 0);
        int mapOffset = ReadOffset(file, 4);
        int dataLength = ReadLength(file, 8);
        int mapLength = ReadLength(file, 12);
        CheckRange(file, dataOffset, dataLength, "DFONT data section");
        CheckRange(file, mapOffset, mapLength, "DFONT resource map");

        int typeList = checked(mapOffset + ReadUInt16(file, checked(mapOffset + 24)));
        CheckRange(file, typeList, 2, "DFONT type list");
        int typeCount = checked(ReadUInt16(file, typeList) + 1);
        int entries = checked(typeList + 2);
        CheckRange(file, entries, checked(typeCount * 8), "DFONT type entries");

        for (int typeIndex = 0; typeIndex < typeCount; typeIndex++)
        {
            int typeEntry = checked(entries + typeIndex * 8);
            string type = Encoding.ASCII.GetString(file, typeEntry, 4);
            if (type != "sfnt")
            {
                continue;
            }

            int resourceCount = checked(ReadUInt16(file, typeEntry + 4) + 1);
            int references = checked(typeList + ReadUInt16(file, typeEntry + 6));
            CheckRange(file, references, checked(resourceCount * 12), "DFONT sfnt references");
            int relativeDataOffset = ReadInt24(file, references + 5);
            int resource = checked(dataOffset + relativeDataOffset);
            int length = ReadLength(file, resource);
            CheckRange(file, checked(resource + 4), length, "DFONT sfnt resource");
            File.WriteAllBytes(output, file.AsSpan(resource + 4, length).ToArray());
            return;
        }

        throw new InvalidDataException("DFONT does not contain an sfnt font resource.");
    }

    private static int ReadOffset(byte[] file, int offset)
    {
        uint value = ReadUInt32(file, offset);
        if (value > int.MaxValue)
        {
            throw new InvalidDataException("DFONT offset is too large.");
        }
        return (int)value;
    }

    private static int ReadLength(byte[] file, int offset)
    {
        uint value = ReadUInt32(file, offset);
        if (value > int.MaxValue)
        {
            throw new InvalidDataException("DFONT section is too large.");
        }
        return (int)value;
    }

    private static ushort ReadUInt16(byte[] file, int offset)
    {
        CheckRange(file, offset, 2, "DFONT integer");
        return BinaryPrimitives.ReadUInt16BigEndian(file.AsSpan(offset, 2));
    }

    private static uint ReadUInt32(byte[] file, int offset)
    {
        CheckRange(file, offset, 4, "DFONT integer");
        return BinaryPrimitives.ReadUInt32BigEndian(file.AsSpan(offset, 4));
    }

    private static int ReadInt24(byte[] file, int offset)
    {
        CheckRange(file, offset, 3, "DFONT resource offset");
        return file[offset] << 16 | file[offset + 1] << 8 | file[offset + 2];
    }

    private static void CheckRange(byte[] file, int offset, int length, string field)
    {
        if (offset < 0 || length < 0 || offset > file.Length - length)
        {
            throw new InvalidDataException($"{field} is outside the file.");
        }
    }

    private static byte[] BuildTestDfont(byte[] payload)
    {
        const int dataOffset = 256;
        int dataLength = checked(payload.Length + 4);
        int mapOffset = checked((dataOffset + dataLength + 3) & ~3);
        const int mapLength = 50;
        byte[] file = new byte[checked(mapOffset + mapLength)];
        WriteUInt32(file, 0, dataOffset);
        WriteUInt32(file, 4, mapOffset);
        WriteUInt32(file, 8, dataLength);
        WriteUInt32(file, 12, mapLength);
        file.AsSpan(0, 16).CopyTo(file.AsSpan(mapOffset, 16));
        WriteUInt32(file, dataOffset, payload.Length);
        payload.CopyTo(file, dataOffset + 4);

        WriteUInt16(file, mapOffset + 24, 28);
        WriteUInt16(file, mapOffset + 26, mapLength);
        int typeList = mapOffset + 28;
        WriteUInt16(file, typeList, 0);
        "sfnt"u8.CopyTo(file.AsSpan(typeList + 2, 4));
        WriteUInt16(file, typeList + 6, 0);
        WriteUInt16(file, typeList + 8, 10);
        int reference = typeList + 10;
        WriteUInt16(file, reference, 128);
        WriteUInt16(file, reference + 2, ushort.MaxValue);
        return file;
    }

    private static void WriteUInt16(byte[] file, int offset, int value)
    {
        BinaryPrimitives.WriteUInt16BigEndian(file.AsSpan(offset, 2), checked((ushort)value));
    }

    private static void WriteUInt32(byte[] file, int offset, int value)
    {
        BinaryPrimitives.WriteUInt32BigEndian(file.AsSpan(offset, 4), checked((uint)value));
    }
}
