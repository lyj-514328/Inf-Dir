using System.Diagnostics;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace InfDir.EmailView;

internal sealed class EmailViewerForm : Form
{
    private const string VirtualHost = "email-view.local";

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    private readonly ParsedEmail _email;
    private readonly WebView2 _webView = new() { Dock = DockStyle.Fill };
    private readonly Dictionary<string, EmailAttachment> _attachments;
    private readonly WindowPlacement? _placement;

    public EmailViewerForm(ParsedEmail email, WindowPlacement? placement)
    {
        _email = email;
        _placement = placement;
        _attachments = email.Attachments.ToDictionary(attachment => attachment.Info.Id);

        Text = string.IsNullOrWhiteSpace(email.Document.Subject)
            ? $"{email.Document.SourceFileName} - Email View"
            : $"{email.Document.Subject} - Email View";
        MinimumSize = new Size(420, 320);
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(980, 720);
        Opacity = 0;
        ShowInTaskbar = false;
        Controls.Add(_webView);

        ApplyPlacement();
        Load += HandleLoad;
    }

    private void ApplyPlacement()
    {
        if (_placement is null)
        {
            return;
        }

        StartPosition = FormStartPosition.Manual;
        Location = new Point(_placement.X, _placement.Y);
        ClientSize = new Size(_placement.ClientWidth, _placement.ClientHeight);
    }

    private async void HandleLoad(object? sender, EventArgs eventArgs)
    {
        try
        {
            var webRoot = Path.Combine(AppContext.BaseDirectory, "email-view-web");
            if (!Directory.Exists(webRoot))
            {
                throw new DirectoryNotFoundException($"Web assets were not found: {webRoot}");
            }

            var userData = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Inf-Dir",
                "WebView2",
                "email-view");
            Directory.CreateDirectory(userData);

            var environment = await CoreWebView2Environment.CreateAsync(null, userData);
            await _webView.EnsureCoreWebView2Async(environment);
            ConfigureWebView(_webView.CoreWebView2, webRoot);
            _webView.CoreWebView2.Navigate($"https://{VirtualHost}/index.html");
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                this,
                $"无法启动邮件查看器：{exception.Message}",
                "Email View",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            Close();
        }
    }

    private void ConfigureWebView(CoreWebView2 core, string webRoot)
    {
        core.SetVirtualHostNameToFolderMapping(
            VirtualHost,
            webRoot,
            CoreWebView2HostResourceAccessKind.DenyCors);

        core.Settings.AreDevToolsEnabled = false;
        core.Settings.AreDefaultContextMenusEnabled = false;
        core.Settings.IsStatusBarEnabled = false;
        core.Settings.IsZoomControlEnabled = true;
        core.Settings.IsBuiltInErrorPageEnabled = false;

        core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
        core.WebResourceRequested += HandleWebResourceRequested;
        core.WebMessageReceived += HandleWebMessageReceived;
        core.NavigationStarting += HandleNavigationStarting;
        core.NewWindowRequested += (_, args) => args.Handled = true;
        core.DownloadStarting += (_, args) => args.Cancel = true;
    }

    private void HandleNavigationStarting(object? sender, CoreWebView2NavigationStartingEventArgs args)
    {
        if (!Uri.TryCreate(args.Uri, UriKind.Absolute, out var uri) ||
            (!uri.Host.Equals(VirtualHost, StringComparison.OrdinalIgnoreCase) && uri.Scheme != "about"))
        {
            args.Cancel = true;
        }
    }

    private void HandleWebResourceRequested(object? sender, CoreWebView2WebResourceRequestedEventArgs args)
    {
        if (!Uri.TryCreate(args.Request.Uri, UriKind.Absolute, out var uri))
        {
            args.Response = BlockedResponse();
            return;
        }

        if (!uri.Host.Equals(VirtualHost, StringComparison.OrdinalIgnoreCase))
        {
            if (uri.Scheme is "http" or "https")
            {
                args.Response = BlockedResponse();
            }
            return;
        }

        const string inlinePrefix = "/inline/";
        if (!uri.AbsolutePath.StartsWith(inlinePrefix, StringComparison.Ordinal))
        {
            return;
        }

        var id = Uri.UnescapeDataString(uri.AbsolutePath[inlinePrefix.Length..]);
        if (!_attachments.TryGetValue(id, out var attachment) || !attachment.Info.Inline)
        {
            args.Response = _webView.CoreWebView2.Environment.CreateWebResourceResponse(
                Stream.Null,
                404,
                "Not Found",
                "Content-Type: text/plain\r\nCache-Control: no-store");
            return;
        }

        args.Response = _webView.CoreWebView2.Environment.CreateWebResourceResponse(
            new MemoryStream(attachment.Data, writable: false),
            200,
            "OK",
            $"Content-Type: {attachment.Info.ContentType}\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff");
    }

    private CoreWebView2WebResourceResponse BlockedResponse()
    {
        return _webView.CoreWebView2.Environment.CreateWebResourceResponse(
            Stream.Null,
            403,
            "Blocked",
            "Content-Type: text/plain\r\nCache-Control: no-store");
    }

    private void HandleWebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs args)
    {
        try
        {
            using var message = JsonDocument.Parse(args.WebMessageAsJson);
            var root = message.RootElement;
            if (!root.TryGetProperty("type", out var typeElement))
            {
                return;
            }

            switch (typeElement.GetString())
            {
                case "ready":
                    _webView.CoreWebView2.PostWebMessageAsJson(
                        JsonSerializer.Serialize(_email.Document, JsonOptions));
                    ShowViewer();
                    break;
                case "saveAttachment":
                    SaveAttachment(ReadString(root, "id"));
                    break;
                case "openLink":
                    OpenExternalLink(ReadString(root, "url"));
                    break;
            }
        }
        catch (JsonException)
        {
            // Ignore malformed messages from the isolated renderer.
        }
    }

    private void ShowViewer()
    {
        ShowInTaskbar = true;
        Opacity = 1;
        if (_placement?.Maximized == true)
        {
            WindowState = FormWindowState.Maximized;
        }
        Activate();
        _webView.Focus();
    }

    private void SaveAttachment(string? id)
    {
        if (id is null || !_attachments.TryGetValue(id, out var attachment))
        {
            return;
        }

        using var dialog = new SaveFileDialog
        {
            FileName = attachment.Info.Name,
            Filter = "所有文件 (*.*)|*.*",
            OverwritePrompt = true,
            RestoreDirectory = true,
        };
        if (dialog.ShowDialog(this) != DialogResult.OK)
        {
            return;
        }

        try
        {
            File.WriteAllBytes(dialog.FileName, attachment.Data);
            _webView.CoreWebView2.PostWebMessageAsJson(
                JsonSerializer.Serialize(new { type = "attachmentSaved", id }, JsonOptions));
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                this,
                $"无法保存附件：{exception.Message}",
                "Email View",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }

    private static void OpenExternalLink(string? value)
    {
        if (value is null || value.Length > 4096 ||
            !Uri.TryCreate(value, UriKind.Absolute, out var uri) ||
            uri.Scheme is not ("http" or "https" or "mailto"))
        {
            return;
        }

        try
        {
            Process.Start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true });
        }
        catch
        {
            // The shell may have no handler for the selected URI scheme.
        }
    }

    private static string? ReadString(JsonElement root, string property)
    {
        return root.TryGetProperty(property, out var element) && element.ValueKind == JsonValueKind.String
            ? element.GetString()
            : null;
    }
}
