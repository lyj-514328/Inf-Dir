using System.Diagnostics;
using System.IO.Compression;
using System.Net;
using System.Text;
using MuPdfDocument = MuPDF.NET.Document;

namespace mupdf_view;

internal sealed class PreparedDocument : IDisposable
{
    private readonly string? _temporaryDirectory;

    private PreparedDocument(string filePath, string displayName, string? temporaryDirectory)
    {
        FilePath = filePath;
        DisplayName = displayName;
        _temporaryDirectory = temporaryDirectory;
    }

    public string FilePath { get; }
    public string DisplayName { get; }

    public static PreparedDocument Direct(string filePath)
    {
        return new PreparedDocument(filePath, Path.GetFileName(filePath), null);
    }

    public static PreparedDocument Temporary(
        string filePath,
        string displayName,
        string temporaryDirectory)
    {
        return new PreparedDocument(filePath, displayName, temporaryDirectory);
    }

    public void Dispose()
    {
        if (_temporaryDirectory is null)
        {
            return;
        }

        try
        {
            Directory.Delete(_temporaryDirectory, recursive: true);
        }
        catch
        {
            // Temporary files are best-effort cleanup; the OS will reclaim the temp tree later.
        }
    }
}

internal static class DocumentPreparation
{
    private const int MaxTcrOutputBytes = 256 * 1024 * 1024;
    private const long MaxComicArchiveBytes = 512L * 1024 * 1024;
    private const int MaxComicPages = 10_000;

    private static readonly HashSet<string> ComicImageExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".jpg", ".jpeg", ".jfif", ".png", ".gif", ".bmp", ".webp", ".tif", ".tiff",
        ".avif", ".jxl", ".jp2", ".j2k",
    };

    public static void SelfTest()
    {
        string temp = CreateTempDirectory("self-test-source");
        try
        {
            string source = Path.Combine(temp, "self-test.tcr");
            using (var output = File.Create(source))
            {
                output.Write("!!8-Bit!!"u8);
                for (int index = 0; index < 256; index++)
                {
                    byte[] entry = index == 42 ? "<html><body>TCR test</body></html>"u8.ToArray() : Array.Empty<byte>();
                    output.WriteByte(checked((byte)entry.Length));
                    output.Write(entry);
                }
                output.WriteByte(42);
            }

            using PreparedDocument prepared = Prepare(source);
            using var document = new MuPdfDocument(prepared.FilePath);
            if (document.PageCount == 0)
            {
                throw new InvalidDataException("MuPDF could not open the prepared TCR document.");
            }
        }
        finally
        {
            Directory.Delete(temp, recursive: true);
        }
    }

    public static PreparedDocument Prepare(string source)
    {
        string extension = Path.GetExtension(source);
        if (extension.Equals(".djvu", StringComparison.OrdinalIgnoreCase) ||
            extension.Equals(".djv", StringComparison.OrdinalIgnoreCase))
        {
            return ConvertDjvu(source);
        }

        if (s_visioExtensions.Contains(extension))
        {
            return ConvertVisio(source);
        }

        if (extension.Equals(".dwg", StringComparison.OrdinalIgnoreCase) ||
            extension.Equals(".dxf", StringComparison.OrdinalIgnoreCase))
        {
            return ConvertCad(source);
        }

        if (extension.Equals(".fbz", StringComparison.OrdinalIgnoreCase) ||
            extension.Equals(".fb2z", StringComparison.OrdinalIgnoreCase))
        {
            return ExtractFictionBook(source);
        }

        if (extension.Equals(".tcr", StringComparison.OrdinalIgnoreCase))
        {
            return DecompressTcr(source);
        }

        if (extension.Equals(".cbr", StringComparison.OrdinalIgnoreCase))
        {
            return ConvertCbr(source);
        }
        return PreparedDocument.Direct(source);
    }

    private static readonly HashSet<string> s_visioExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".vsd", ".vsdm", ".vsdx", ".vss", ".vssm", ".vssx",
        ".vst", ".vstm", ".vstx", ".vdx", ".vdw", ".vsx", ".vtx",
        ".wps",
    };

    private static PreparedDocument ConvertVisio(string source)
    {
        string executable = FindLibreOffice()
            ?? throw new InvalidOperationException(
                "Visio 预览需要 LibreOffice 转换运行时；请重新运行 plugins\\build.bat，或设置 INF_DIR_LIBREOFFICE_PATH。");
        string temp = CreateTempDirectory("libreoffice");
        try
        {
            string profile = Path.Combine(temp, "profile");
            string outputDirectory = Path.Combine(temp, "output");
            Directory.CreateDirectory(profile);
            Directory.CreateDirectory(outputDirectory);

            string profileUri = new Uri(profile + Path.DirectorySeparatorChar).AbsoluteUri;
            ProcessResult result = RunTool(
                executable,
                new[]
                {
                    "--headless", "--nologo", "--nodefault", "--nofirststartwizard", "--norestore",
                    "--nolockcheck", $"-env:UserInstallation={profileUri}",
                    "--convert-to", "pdf", "--outdir", outputDirectory, source,
                },
                temp,
                timeoutMilliseconds: 120_000);
            string output = Path.Combine(outputDirectory, Path.GetFileNameWithoutExtension(source) + ".pdf");
            if (!result.Success || !File.Exists(output))
            {
                string detail = FirstNonEmpty(result.StandardError, result.StandardOutput, "LibreOffice 没有生成 PDF。");
                throw new InvalidOperationException($"Visio 转 PDF 失败：{detail}");
            }
            return PreparedDocument.Temporary(output, Path.GetFileName(source), temp);
        }
        catch
        {
            CleanupTemporaryDirectory(temp);
            throw;
        }
    }

    private static string? FindLibreOffice()
    {
        string? configured = Environment.GetEnvironmentVariable("INF_DIR_LIBREOFFICE_PATH");
        IEnumerable<string> candidates = new[]
        {
            configured,
            Path.Combine(AppContext.BaseDirectory, "libreoffice", "program", "soffice.exe"),
            Environment.GetEnvironmentVariable("ProgramFiles") is { Length: > 0 } programFiles
                ? Path.Combine(programFiles, "LibreOffice", "program", "soffice.exe")
                : null,
            Environment.GetEnvironmentVariable("ProgramFiles(x86)") is { Length: > 0 } programFilesX86
                ? Path.Combine(programFilesX86, "LibreOffice", "program", "soffice.exe")
                : null,
        }.Where(path => !string.IsNullOrWhiteSpace(path)).Select(path => path!);

        foreach (string candidate in candidates)
        {
            if (File.Exists(candidate))
            {
                return candidate;
            }
            if (Directory.Exists(candidate))
            {
                string direct = Path.Combine(candidate, "soffice.exe");
                string nested = Path.Combine(candidate, "program", "soffice.exe");
                if (File.Exists(direct))
                {
                    return direct;
                }
                if (File.Exists(nested))
                {
                    return nested;
                }
            }
        }

        return FindOnPath("soffice.exe") ?? FindOnPath("soffice.com");
    }

    private static PreparedDocument ConvertDjvu(string source)
    {
        string executable = FindBundledTool("djvulibre", "ddjvu.exe")
            ?? throw new InvalidOperationException(
                "DjVu 查看需要内置的 DjVuLibre 运行时；请重新运行 plugins\\build.bat。");
        string temp = CreateTempDirectory("djvu");
        string output = Path.Combine(temp, Path.GetFileNameWithoutExtension(source) + ".pdf");
        RunTool(executable, new[] { "-format=pdf", source, output }, temp);
        EnsureOutput(output, "DjVu 转换");
        return PreparedDocument.Temporary(output, Path.GetFileName(source), temp);
    }

    private static PreparedDocument ConvertCad(string source)
    {
        string svgExecutable = FindBundledTool("libredwg", "dwg2SVG.exe")
            ?? throw new InvalidOperationException(
                "CAD 预览需要内置的 LibreDWG 运行时；请重新运行 plugins\\build.bat。");
        string temp = CreateTempDirectory("dwg");
        string input = source;
        if (Path.GetExtension(source).Equals(".dxf", StringComparison.OrdinalIgnoreCase))
        {
            string dxfExecutable = FindBundledTool("libredwg", "dxf2dwg.exe")
                ?? throw new InvalidOperationException("DXF 预览需要 LibreDWG 的 dxf2dwg.exe。");
            input = Path.Combine(temp, Path.GetFileNameWithoutExtension(source) + ".dwg");
            ProcessResult conversion = RunTool(
                dxfExecutable,
                new[] { "-y", "-o", input, source },
                temp);
            if (!conversion.Success)
            {
                throw new InvalidOperationException(
                    $"DXF 转换失败：{FirstNonEmpty(conversion.StandardError, "LibreDWG 未生成 DWG。")}");
            }
            EnsureOutput(input, "DXF 转换");
        }

        string output = Path.Combine(temp, Path.GetFileNameWithoutExtension(source) + ".svg");
        ProcessResult result = RunTool(svgExecutable, new[] { input }, temp, captureOutput: true);
        if (!result.Success || string.IsNullOrWhiteSpace(result.StandardOutput))
        {
            throw new InvalidOperationException(
                $"CAD 转 SVG 失败：{FirstNonEmpty(result.StandardError, "LibreDWG 没有输出有效 SVG。")}");
        }
        File.WriteAllText(output, result.StandardOutput, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        return PreparedDocument.Temporary(output, Path.GetFileName(source), temp);
    }

    private static PreparedDocument ExtractFictionBook(string source)
    {
        string temp = CreateTempDirectory("fictionbook");
        string? entryName = null;
        try
        {
            using ZipArchive archive = ZipFile.OpenRead(source);
            ZipArchiveEntry? entry = archive.Entries.FirstOrDefault(entry =>
                Path.GetExtension(entry.FullName).Equals(".fb2", StringComparison.OrdinalIgnoreCase));
            if (entry is null)
            {
                throw new InvalidOperationException("压缩电子书中没有找到 FB2 文件。");
            }
            entryName = Path.GetFileName(entry.FullName);
            string output = Path.Combine(temp, entryName);
            entry.ExtractToFile(output, overwrite: true);
            return PreparedDocument.Temporary(output, Path.GetFileName(source), temp);
        }
        catch
        {
            Directory.Delete(temp, recursive: true);
            throw;
        }
    }

    private static PreparedDocument ConvertCbr(string source)
    {
        string executable = FindComicExtractor()
            ?? throw new InvalidOperationException(
                "CBR preview requires the archive-view extraction runtime; run plugins\\build.bat first.");
        string temp = CreateTempDirectory("cbr");
        string extracted = Path.Combine(temp, "extracted");
        Directory.CreateDirectory(extracted);
        try
        {
            bool usesArchiveViewer = Path.GetFileName(executable)
                .Equals("archive-view.exe", StringComparison.OrdinalIgnoreCase);
            string[] arguments = usesArchiveViewer
                ? new[] { "--extract-comic", source, extracted }
                : new[] { "x", source, $"-o{extracted}", "-y", "-aoa" };
            ProcessResult result = RunTool(executable, arguments, temp, timeoutMilliseconds: 120_000);
            if (!result.Success)
            {
                string detail = FirstNonEmpty(result.StandardError, result.StandardOutput, "The archive extractor could not extract the CBR archive.");
                throw new InvalidOperationException($"CBR extraction failed: {detail}");
            }

            var pages = new List<(string FilePath, string EntryName)>();
            long totalBytes = 0;
            foreach (string file in Directory.EnumerateFiles(extracted, "*", SearchOption.AllDirectories))
            {
                string relative = Path.GetRelativePath(extracted, file);
                if (Path.IsPathRooted(relative) || relative == ".." ||
                    relative.StartsWith(".." + Path.DirectorySeparatorChar, StringComparison.Ordinal))
                {
                    throw new InvalidOperationException("CBR archive contains an unsafe path.");
                }

                if (!ComicImageExtensions.Contains(Path.GetExtension(file))) continue;
                FileInfo info = new(file);
                totalBytes = checked(totalBytes + info.Length);
                if (totalBytes > MaxComicArchiveBytes)
                {
                    throw new InvalidOperationException("CBR image data exceeds the 512 MiB preview limit.");
                }
                pages.Add((file, relative.Replace(Path.DirectorySeparatorChar, '/')));
            }

            if (pages.Count == 0)
            {
                throw new InvalidOperationException("CBR archive contains no supported comic images.");
            }
            if (pages.Count > MaxComicPages)
            {
                throw new InvalidOperationException("CBR archive contains too many comic pages.");
            }

            pages.Sort((left, right) => CompareComicEntryNames(left.EntryName, right.EntryName));
            string output = Path.Combine(temp, Path.GetFileNameWithoutExtension(source) + ".cbz");
            using (ZipArchive archive = ZipFile.Open(output, ZipArchiveMode.Create))
            {
                foreach ((string filePath, string entryName) in pages)
                {
                    archive.CreateEntryFromFile(filePath, entryName, CompressionLevel.NoCompression);
                }
            }
            return PreparedDocument.Temporary(output, Path.GetFileName(source), temp);
        }
        catch
        {
            CleanupTemporaryDirectory(temp);
            throw;
        }
    }

    private static int CompareComicEntryNames(string left, string right)
    {
        int leftIndex = 0;
        int rightIndex = 0;
        while (leftIndex < left.Length && rightIndex < right.Length)
        {
            char leftChar = left[leftIndex];
            char rightChar = right[rightIndex];
            if (char.IsDigit(leftChar) && char.IsDigit(rightChar))
            {
                int leftEnd = leftIndex;
                while (leftEnd < left.Length && char.IsDigit(left[leftEnd])) leftEnd++;
                int rightEnd = rightIndex;
                while (rightEnd < right.Length && char.IsDigit(right[rightEnd])) rightEnd++;
                int leftSignificant = leftIndex;
                while (leftSignificant + 1 < leftEnd && left[leftSignificant] == '0') leftSignificant++;
                int rightSignificant = rightIndex;
                while (rightSignificant + 1 < rightEnd && right[rightSignificant] == '0') rightSignificant++;
                int leftDigits = leftEnd - leftSignificant;
                int rightDigits = rightEnd - rightSignificant;
                if (leftDigits != rightDigits) return leftDigits.CompareTo(rightDigits);
                int numeric = string.Compare(
                    left, leftSignificant, right, rightSignificant, leftDigits,
                    StringComparison.OrdinalIgnoreCase);
                if (numeric != 0) return numeric;
                leftIndex = leftEnd;
                rightIndex = rightEnd;
                continue;
            }

            int text = char.ToUpperInvariant(leftChar).CompareTo(char.ToUpperInvariant(rightChar));
            if (text != 0) return text;
            leftIndex++;
            rightIndex++;
        }
        return left.Length - leftIndex == right.Length - rightIndex
            ? StringComparer.OrdinalIgnoreCase.Compare(left, right)
            : (left.Length - leftIndex).CompareTo(right.Length - rightIndex);
    }

    private static PreparedDocument DecompressTcr(string source)
    {
        byte[] input = File.ReadAllBytes(source);
        ReadOnlySpan<byte> header = "!!8-Bit!!"u8;
        if (input.Length < header.Length || !input.AsSpan(0, header.Length).SequenceEqual(header))
        {
            throw new InvalidOperationException("TCR 文件头无效。");
        }

        int offset = header.Length;
        var dictionary = new byte[256][];
        for (int index = 0; index < dictionary.Length; index++)
        {
            if (offset >= input.Length)
            {
                throw new InvalidOperationException("TCR 字典不完整。");
            }
            int length = input[offset++];
            if (offset + length > input.Length)
            {
                throw new InvalidOperationException("TCR 字典条目越界。");
            }
            dictionary[index] = input.AsSpan(offset, length).ToArray();
            offset += length;
        }

        using var decoded = new MemoryStream();
        while (offset < input.Length)
        {
            byte[] entry = dictionary[input[offset++]];
            if (decoded.Length + entry.Length > MaxTcrOutputBytes)
            {
                throw new InvalidOperationException("TCR 解压结果超过 256 MiB 安全上限。");
            }
            decoded.Write(entry);
        }

        string text = DecodeBookText(decoded.ToArray());
        if (!LooksLikeHtml(text))
        {
            text = $"<!doctype html><meta charset=\"utf-8\"><pre>{WebUtility.HtmlEncode(text)}</pre>";
        }

        string temp = CreateTempDirectory("tcr");
        string output = Path.Combine(temp, Path.GetFileNameWithoutExtension(source) + ".html");
        File.WriteAllText(output, text, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        return PreparedDocument.Temporary(output, Path.GetFileName(source), temp);
    }

    private static string DecodeBookText(byte[] data)
    {
        try
        {
            return new UTF8Encoding(false, throwOnInvalidBytes: true).GetString(data);
        }
        catch (DecoderFallbackException)
        {
            return Encoding.Latin1.GetString(data);
        }
    }

    private static bool LooksLikeHtml(string text)
    {
        ReadOnlySpan<char> trimmed = text.AsSpan().TrimStart();
        return trimmed.StartsWith("<!doctype", StringComparison.OrdinalIgnoreCase) ||
               trimmed.StartsWith("<html", StringComparison.OrdinalIgnoreCase) ||
               trimmed.StartsWith("<body", StringComparison.OrdinalIgnoreCase) ||
               trimmed.StartsWith("<head", StringComparison.OrdinalIgnoreCase);
    }

    private static string? FindBundledTool(string directory, string executable)
    {
        string path = Path.Combine(AppContext.BaseDirectory, directory, executable);
        return File.Exists(path) ? path : null;
    }

    private static string? FindSevenZip()
    {
        string? configured = Environment.GetEnvironmentVariable("INF_DIR_7Z_PATH");
        IEnumerable<string> candidates = new[]
        {
            configured,
            Path.Combine(AppContext.BaseDirectory, "7za.exe"),
            Path.Combine(AppContext.BaseDirectory, "..", "inf-dir.7z-archive", "7za.exe"),
            Path.Combine(AppContext.BaseDirectory, "..", "7z-archive", "7za.exe"),
        }.Where(path => !string.IsNullOrWhiteSpace(path)).Select(path => path!);

        foreach (string candidate in candidates)
        {
            if (File.Exists(candidate)) return Path.GetFullPath(candidate);
            if (!Directory.Exists(candidate)) continue;
            foreach (string executable in new[] { "7za.exe", "7z.exe" })
            {
                string nested = Path.Combine(candidate, executable);
                if (File.Exists(nested)) return nested;
            }
        }

        return FindOnPath("7za.exe") ?? FindOnPath("7z.exe");
    }

    private static string? FindComicExtractor()
    {
        string? configured = Environment.GetEnvironmentVariable("INF_DIR_ARCHIVE_VIEW_PATH");
        IEnumerable<string> candidates = new[]
        {
            configured,
            Path.Combine(AppContext.BaseDirectory, "archive-view.exe"),
            Path.Combine(AppContext.BaseDirectory, "..", "inf-dir.archive-view", "archive-view.exe"),
            Path.Combine(AppContext.BaseDirectory, "..", "archive-view", "archive-view.exe"),
        }.Where(path => !string.IsNullOrWhiteSpace(path)).Select(path => path!);

        foreach (string candidate in candidates)
        {
            if (File.Exists(candidate)) return Path.GetFullPath(candidate);
        }

        return FindSevenZip();
    }

    private static string? FindOnPath(string executable)
    {
        string? pathValue = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrWhiteSpace(pathValue))
        {
            return null;
        }
        foreach (string directory in pathValue.Split(Path.PathSeparator))
        {
            string candidate = Path.Combine(directory.Trim(), executable);
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }
        return null;
    }

    private static string CreateTempDirectory(string purpose)
    {
        string directory = Path.Combine(
            Path.GetTempPath(), "Inf-Dir", "mupdf-view", $"{purpose}-{Guid.NewGuid():N}");
        Directory.CreateDirectory(directory);
        return directory;
    }

    private static void CleanupTemporaryDirectory(string directory)
    {
        try
        {
            Directory.Delete(directory, recursive: true);
        }
        catch
        {
            // Temporary files are best-effort cleanup; the OS will reclaim the temp tree later.
        }
    }

    private static void EnsureOutput(string output, string operation)
    {
        if (!File.Exists(output) || new FileInfo(output).Length == 0)
        {
            throw new InvalidOperationException($"{operation}没有生成有效输出。");
        }
    }

    private static ProcessResult RunTool(
        string executable,
        IEnumerable<string> arguments,
        string workingDirectory,
        bool captureOutput = false,
        int timeoutMilliseconds = 60_000)
    {
        using var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = executable,
                WorkingDirectory = workingDirectory,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardError = true,
                RedirectStandardOutput = captureOutput,
            },
        };
        foreach (string argument in arguments)
        {
            process.StartInfo.ArgumentList.Add(argument);
        }
        if (!process.Start())
        {
            throw new InvalidOperationException($"无法启动外部转换器：{executable}");
        }

        Task<string> standardErrorTask = process.StandardError.ReadToEndAsync();
        Task<string> standardOutputTask = captureOutput
            ? process.StandardOutput.ReadToEndAsync()
            : Task.FromResult(string.Empty);
        if (!process.WaitForExit(timeoutMilliseconds))
        {
            try
            {
                process.Kill(entireProcessTree: true);
            }
            catch
            {
                // The process may have exited between the timeout and Kill call.
            }
            throw new TimeoutException($"外部转换器超时：{Path.GetFileName(executable)}");
        }
        process.WaitForExit();
        return new ProcessResult(
            process.ExitCode == 0,
            standardOutputTask.GetAwaiter().GetResult(),
            standardErrorTask.GetAwaiter().GetResult());
    }

    private static string FirstNonEmpty(params string[] values)
    {
        return values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value))?.Trim()
            ?? "未知错误";
    }

    private sealed record ProcessResult(bool Success, string StandardOutput, string StandardError);
}
