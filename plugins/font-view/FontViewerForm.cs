using System.Net;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace InfDir.FontView;

internal sealed class FontViewerForm : Form
{
    private const string VirtualHost = "font-view.local";
    private readonly string _source;
    private readonly WindowPlacement? _placement;
    private readonly WebView2 _webView = new() { Dock = DockStyle.Fill };
    private string? _temporaryDirectory;

    public FontViewerForm(string source, WindowPlacement? placement)
    {
        _source = source;
        _placement = placement;
        Text = $"{Path.GetFileName(source)} - 字体查看器";
        MinimumSize = new Size(480, 360);
        ClientSize = new Size(960, 720);
        StartPosition = placement is null ? FormStartPosition.CenterScreen : FormStartPosition.Manual;
        Opacity = 0;
        ShowInTaskbar = false;
        Controls.Add(_webView);
        ApplyPlacement();
        Load += HandleLoad;
    }

    private void ApplyPlacement()
    {
        if (_placement is null) return;
        Location = new Point(_placement.X, _placement.Y);
        ClientSize = new Size(_placement.ClientWidth, _placement.ClientHeight);
    }

    private async void HandleLoad(object? sender, EventArgs eventArgs)
    {
        try
        {
            _temporaryDirectory = Path.Combine(Path.GetTempPath(), "Inf-Dir", "font-view", Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(_temporaryDirectory);
            string displayExtension = Path.GetExtension(_source).ToLowerInvariant();
            string webExtension = displayExtension == ".dfont" ? ".ttf" : displayExtension;
            string fontFile = "source" + webExtension;
            string preparedFont = Path.Combine(_temporaryDirectory, fontFile);
            if (displayExtension == ".dfont")
            {
                FontPreparation.ExtractDfont(_source, preparedFont);
            }
            else
            {
                File.Copy(_source, preparedFont);
            }
            File.WriteAllText(
                Path.Combine(_temporaryDirectory, "index.html"),
                BuildHtml(fontFile, displayExtension, webExtension));

            string userData = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Inf-Dir", "WebView2", "font-view");
            Directory.CreateDirectory(userData);
            CoreWebView2Environment environment = await CoreWebView2Environment.CreateAsync(null, userData);
            await _webView.EnsureCoreWebView2Async(environment);
            CoreWebView2 core = _webView.CoreWebView2;
            core.SetVirtualHostNameToFolderMapping(VirtualHost, _temporaryDirectory, CoreWebView2HostResourceAccessKind.DenyCors);
            core.Settings.AreDevToolsEnabled = false;
            core.Settings.AreDefaultContextMenusEnabled = false;
            core.Settings.IsStatusBarEnabled = false;
            core.NavigationStarting += (_, args) =>
            {
                if (!Uri.TryCreate(args.Uri, UriKind.Absolute, out Uri? uri) ||
                    !uri.Host.Equals(VirtualHost, StringComparison.OrdinalIgnoreCase))
                    args.Cancel = true;
            };
            core.NewWindowRequested += (_, args) => args.Handled = true;
            _webView.NavigationCompleted += (_, _) => ShowViewer();
            core.Navigate($"https://{VirtualHost}/index.html");
        }
        catch (Exception exception)
        {
            MessageBox.Show(this, $"无法启动字体查看器：{exception.Message}", "字体查看器", MessageBoxButtons.OK, MessageBoxIcon.Error);
            Close();
        }
    }

    private void ShowViewer()
    {
        ShowInTaskbar = true;
        Opacity = 1;
        if (_placement?.Maximized == true) WindowState = FormWindowState.Maximized;
        Activate();
        _webView.Focus();
    }

    private string BuildHtml(string fontFile, string displayExtension, string webExtension)
    {
        string format = webExtension switch
        {
            ".woff2" => "woff2",
            ".woff" => "woff",
            ".otf" => "opentype",
            ".ttf" or ".ttc" => "truetype",
            _ => string.Empty,
        };
        string formatHint = format.Length == 0 ? string.Empty : $" format('{format}')";
        string name = WebUtility.HtmlEncode(Path.GetFileName(_source));
        string size = new FileInfo(_source).Length switch
        {
            < 1024 => $"{new FileInfo(_source).Length} B",
            < 1024 * 1024 => $"{new FileInfo(_source).Length / 1024d:F1} KB",
            var bytes => $"{bytes / 1024d / 1024d:F1} MB",
        };
        return $$"""
<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; font-src 'self'">
<style>
@font-face{font-family:Preview;src:url('./{{fontFile}}'){{formatHint}};font-display:block}
*{box-sizing:border-box}body{margin:0;background:#f7f8fa;color:#202124;font-family:Segoe UI,sans-serif}
header{height:58px;padding:9px 18px;border-bottom:1px solid #dfe1e5;background:#fff;display:flex;align-items:center;gap:18px}
.meta{min-width:0;flex:1}.name{font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.sub{font-size:12px;color:#687078;margin-top:2px}
label{display:flex;align-items:center;gap:8px;font-size:13px;color:#4b535b}input[type=range]{width:150px}
main{padding:28px clamp(24px,6vw,84px)}#error{display:none;padding:14px;background:#fff1f0;color:#a61d24;border:1px solid #ffccc7}
.sample{font-family:Preview,Segoe UI,sans-serif;outline:none;line-height:1.35;overflow-wrap:anywhere;border-bottom:1px solid #e2e5e9;padding:22px 0}
#hero{font-size:72px}.row{font-size:34px}.small{font-size:20px;line-height:1.6}
</style></head><body><header><div class="meta"><div class="name">{{name}}</div><div class="sub">{{displayExtension.TrimStart('.').ToUpperInvariant()}} · {{size}}</div></div>
<label>字号 <input id="size" type="range" min="24" max="128" value="72"><output id="value">72 px</output></label></header>
<main><div id="error">字体无法由系统的 WebView2 字体引擎加载。</div>
<div id="hero" class="sample" contenteditable="true" spellcheck="false">Inf-Dir 文件管理器</div>
<div class="sample row" contenteditable="true" spellcheck="false">天地玄黄 宇宙洪荒 · 0123456789</div>
<div class="sample row" contenteditable="true" spellcheck="false">The quick brown fox jumps over the lazy dog.</div>
<div class="sample small" contenteditable="true" spellcheck="false">ABCDEFGHIJKLMNOPQRSTUVWXYZ<br>abcdefghijklmnopqrstuvwxyz<br>!@#$%^&amp;*() [] {} &lt;&gt; / \ + =</div></main>
<script>
const slider=document.getElementById('size'),hero=document.getElementById('hero'),value=document.getElementById('value');
slider.addEventListener('input',()=>{hero.style.fontSize=slider.value+'px';value.textContent=slider.value+' px'});
document.fonts.load('32px Preview').then(fonts=>{if(!fonts.length)document.getElementById('error').style.display='block'}).catch(()=>document.getElementById('error').style.display='block');
</script></body></html>
""";
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        _webView.Dispose();
        if (_temporaryDirectory is not null)
        {
            try { Directory.Delete(_temporaryDirectory, recursive: true); } catch { }
        }
        base.OnFormClosed(e);
    }
}
