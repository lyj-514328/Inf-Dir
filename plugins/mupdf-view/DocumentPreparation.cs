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

    private static readonly HashSet<string> LibreOfficeExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".doc", ".dot", ".docm", ".dotm", ".xls", ".xlt", ".xlsb", ".ppt", ".pot", ".pps",
        ".odt", ".ott", ".ods", ".ots", ".odp", ".otp", ".rtf", ".wps", ".wbk",
        ".vsd", ".vsdm", ".vsdx", ".vss", ".vssx", ".vst", ".vstm", ".vstx", ".vdx", ".vdw",
        ".vsx", ".vtx", ".mht",
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

        if (LibreOfficeExtensions.Contains(extension))
        {
            return ConvertWithLibreOffice(source);
        }

        return PreparedDocument.Direct(source);
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

    private static PreparedDocument ConvertWithLibreOffice(string source)
    {
        string executable = FindLibreOffice()
            ?? throw new InvalidOperationException(
                "该格式需要 LibreOffice 转换运行时；请安装 LibreOffice，或设置 INF_DIR_LIBREOFFICE_PATH。");
        string temp = CreateTempDirectory("libreoffice");
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
            Directory.Delete(temp, recursive: true);
            throw new InvalidOperationException($"LibreOffice 转换失败：{detail}");
        }
        return PreparedDocument.Temporary(output, Path.GetFileName(source), temp);
    }

    private static string? FindBundledTool(string directory, string executable)
    {
        string path = Path.Combine(AppContext.BaseDirectory, directory, executable);
        return File.Exists(path) ? path : null;
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
        if (Path.GetFileName(executable).StartsWith("soffice", StringComparison.OrdinalIgnoreCase))
        {
            string pythonHome = Path.Combine(Path.GetDirectoryName(executable)!, "python-core-3.12.13");
            if (Directory.Exists(pythonHome))
            {
                process.StartInfo.Environment["PYTHONHOME"] = pythonHome;
            }
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
