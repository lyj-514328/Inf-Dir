using System.Runtime.InteropServices;
using MuPDF.NET;

namespace mupdf_view;

public sealed class ViewerForm : Form
{
    private const float MinZoom = 0.05f;
    private const float MaxZoom = 16f;

    private readonly Document _doc;
    private readonly string _fileName;
    private readonly ToolStrip _toolbar = new();
    private readonly ToolStripLabel _pageLabel = new();
    private readonly ToolStripTextBox _pageBox = new();
    private readonly ToolStripLabel _zoomLabel = new();
    private readonly PageCanvas _canvas;

    private int _pageIndex;
    private float _zoom = 1f;
    private ZoomMode _zoomMode = ZoomMode.FitWidth;
    private Bitmap? _pageBitmap;
    private TextPage? _pageText;
    private readonly List<TextChar> _chars = new();

    private enum ZoomMode
    {
        FitWidth,
        FitPage,
        Custom,
    }

    private readonly record struct TextChar(
        float X0, float Y0, float X1, float Y1, char Ch);

    public ViewerForm(string file, WindowPlacement? placement, string? displayName = null)
    {
        _fileName = displayName ?? Path.GetFileName(file);
        try
        {
            _doc = new Document(file);
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, $"无法打开文档：{ex.Message}", "MuPDF 查看器",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            Environment.Exit(1);
            return;
        }

        if (_doc.PageCount == 0)
        {
            MessageBox.Show(this, "文档没有页面。", "MuPDF 查看器",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            Environment.Exit(1);
            return;
        }

        Text = $"{_fileName} - MuPDF 查看器";
        MinimumSize = new Size(480, 360);
        StartPosition = FormStartPosition.CenterScreen;
        KeyPreview = true;

        _canvas = new PageCanvas(this) { Dock = DockStyle.Fill };
        Controls.Add(_canvas);
        Controls.Add(BuildToolbar());

        KeyDown += OnFormKeyDown;
        Load += (_, _) => ApplyPlacement(placement);
        Shown += (_, _) => RenderCurrentPage();
    }

    private ToolStrip BuildToolbar()
    {
        _toolbar.GripStyle = ToolStripGripStyle.Hidden;
        _toolbar.Padding = new Padding(6, 2, 6, 2);
        _toolbar.BackColor = System.Drawing.Color.FromArgb(32, 33, 36);
        _toolbar.ForeColor = System.Drawing.Color.FromArgb(232, 234, 237);

        _toolbar.Items.Add(new ToolStripButton("◀", null, (_, _) => GoToPage(_pageIndex - 1))
        {
            DisplayStyle = ToolStripItemDisplayStyle.Text,
            ToolTipText = "上一页",
        });
        _toolbar.Items.Add(new ToolStripButton("▶", null, (_, _) => GoToPage(_pageIndex + 1))
        {
            DisplayStyle = ToolStripItemDisplayStyle.Text,
            ToolTipText = "下一页",
        });

        _pageBox.TextBox.Width = 52;
        _pageBox.TextBox.BorderStyle = BorderStyle.FixedSingle;
        _pageBox.TextBox.KeyDown += (_, e) =>
        {
            if (e.KeyCode == Keys.Enter)
            {
                if (int.TryParse(_pageBox.Text, out int page) && page >= 1 && page <= _doc.PageCount)
                {
                    GoToPage(page - 1);
                }
                else
                {
                    UpdatePageControls();
                }
            }
        };
        _toolbar.Items.Add(_pageBox);
        _toolbar.Items.Add(_pageLabel);

        _toolbar.Items.Add(new ToolStripSeparator());
        _toolbar.Items.Add(new ToolStripButton("－", null, (_, _) => StepZoom(-0.1f))
        {
            DisplayStyle = ToolStripItemDisplayStyle.Text,
            ToolTipText = "缩小",
        });
        _toolbar.Items.Add(new ToolStripButton("＋", null, (_, _) => StepZoom(0.1f))
        {
            DisplayStyle = ToolStripItemDisplayStyle.Text,
            ToolTipText = "放大",
        });
        _toolbar.Items.Add(new ToolStripButton("适应宽度", null, (_, _) => SetZoomMode(ZoomMode.FitWidth))
        {
            DisplayStyle = ToolStripItemDisplayStyle.Text,
            ToolTipText = "适应宽度",
        });
        _toolbar.Items.Add(new ToolStripButton("适应页面", null, (_, _) => SetZoomMode(ZoomMode.FitPage))
        {
            DisplayStyle = ToolStripItemDisplayStyle.Text,
            ToolTipText = "适应页面",
        });
        _toolbar.Items.Add(_zoomLabel);

        return _toolbar;
    }

    private void ApplyPlacement(WindowPlacement? placement)
    {
        if (placement is null)
        {
            Size = new Size(960, 720);
            CenterToScreen();
            return;
        }
        if (placement.Maximized)
        {
            WindowState = FormWindowState.Maximized;
        }
        else
        {
            Location = new System.Drawing.Point(placement.X, placement.Y);
            ClientSize = new Size((int)placement.ClientWidth, (int)placement.ClientHeight);
        }
    }

    private void GoToPage(int index)
    {
        if (index < 0 || index >= _doc.PageCount)
        {
            return;
        }
        _pageIndex = index;
        RenderCurrentPage();
    }

    private void StepZoom(float delta)
    {
        _zoomMode = ZoomMode.Custom;
        _zoom = Math.Clamp(_zoom + delta, MinZoom, MaxZoom);
        RenderCurrentPage();
    }

    private void SetZoomMode(ZoomMode mode)
    {
        _zoomMode = mode;
        RenderCurrentPage();
    }

    private float ComputeZoom(SizeF pageSizePt)
    {
        if (pageSizePt.Width <= 0 || pageSizePt.Height <= 0)
        {
            return 1f;
        }
        return _zoomMode switch
        {
            ZoomMode.FitWidth => _canvas.ClientSize.Width / pageSizePt.Width,
            ZoomMode.FitPage => Math.Min(
                _canvas.ClientSize.Width / pageSizePt.Width,
                _canvas.ClientSize.Height / pageSizePt.Height),
            _ => _zoom,
        };
    }

    private void RenderCurrentPage()
    {
        try
        {
            _chars.Clear();
            _pageText?.Dispose();
            _pageText = null;

            using (Page page = _doc.LoadPage(_pageIndex))
            {
                SizeF sizePt = new(page.Rect.Width, page.Rect.Height);
                float zoom = ComputeZoom(sizePt);
                _zoom = zoom;
                zoom = Math.Clamp(zoom, MinZoom, MaxZoom);

                var matrix = new Matrix(zoom, zoom);
                var pix = page.GetPixmap(matrix);
                try
                {
                    _pageBitmap?.Dispose();
                    _pageBitmap = PixmapToBitmap(pix);
                }
                finally
                {
                    pix.Dispose();
                }

                _pageText = page.GetTextPage();
                CollectChars(_pageText);
            }
            _canvas.SetPage(_pageBitmap, _zoom, _chars);
            UpdatePageControls();
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, $"渲染失败：{ex.Message}", "MuPDF 查看器",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void CollectChars(TextPage textPage)
    {
        PageInfo info = textPage.ExtractRAWDict();
        foreach (Block block in info.Blocks)
        {
            if (block.Type != 0)
            {
                continue;
            }
            foreach (Line line in block.Lines)
            {
                foreach (Span span in line.Spans)
                {
                    foreach (MuPDF.NET.Char ch in span.Chars)
                    {
                        if (ch.C != '\0')
                        {
                            _chars.Add(new TextChar(
                                ch.Bbox.x0, ch.Bbox.y0,
                                ch.Bbox.x1, ch.Bbox.y1, ch.C));
                        }
                    }
                }
            }
        }
    }

    internal string? GetSelectionText(PointF a, PointF b)
    {
        if (_pageText is null)
        {
            return null;
        }
        try
        {
            return _pageText.ExtractSelection(
                new MuPDF.NET.Point(a.X, a.Y),
                new MuPDF.NET.Point(b.X, b.Y));
        }
        catch
        {
            return null;
        }
    }

    private static Bitmap PixmapToBitmap(Pixmap pix)
    {
        int width = (int)pix.W;
        int height = (int)pix.H;
        var bmp = new Bitmap(width, height, System.Drawing.Imaging.PixelFormat.Format24bppRgb);
        var rect = new Rectangle(0, 0, width, height);
        var bd = bmp.LockBits(rect, System.Drawing.Imaging.ImageLockMode.WriteOnly,
            System.Drawing.Imaging.PixelFormat.Format24bppRgb);
        try
        {
            unsafe
            {
                byte* src = (byte*)pix.SamplesPtr;
                byte* dst = (byte*)bd.Scan0;
                for (int y = 0; y < height; y++)
                {
                    byte* s = src + y * pix.Stride;
                    byte* d = dst + y * bd.Stride;
                    for (int x = 0; x < width; x++)
                    {
                        byte r = s[0], g = s[1], b = s[2];
                        d[0] = b;
                        d[1] = g;
                        d[2] = r;
                        s += 3;
                        d += 3;
                    }
                }
            }
        }
        finally
        {
            bmp.UnlockBits(bd);
        }
        return bmp;
    }

    private void UpdatePageControls()
    {
        _pageBox.Text = (_pageIndex + 1).ToString();
        _pageLabel.Text = $" / {_doc.PageCount}";
        _zoomLabel.Text = $" {_zoom * 100f:F0}%";
    }

    private void OnFormKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Control && e.KeyCode == Keys.C)
        {
            if (_canvas.CopySelection() && e is { } evt)
            {
                evt.Handled = true;
            }
            return;
        }
        switch (e.KeyCode)
        {
            case Keys.PageDown:
            case Keys.Right:
                GoToPage(_pageIndex + 1);
                e.Handled = true;
                break;
            case Keys.PageUp:
            case Keys.Left:
                GoToPage(_pageIndex - 1);
                e.Handled = true;
                break;
            case Keys.Escape:
                Close();
                break;
        }
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        _pageBitmap?.Dispose();
        _pageText?.Dispose();
        _doc.Close();
        base.OnFormClosed(e);
    }

    private sealed class PageCanvas : Panel
    {
        private readonly ViewerForm _owner;
        private readonly PageView _pageView;

        public PageCanvas(ViewerForm owner)
        {
            _owner = owner;
            BackColor = System.Drawing.Color.FromArgb(66, 67, 70);
            DoubleBuffered = true;
            AutoScroll = true;
            _pageView = new PageView(owner);
            Controls.Add(_pageView);
            Resize += (_, _) =>
            {
                if (_owner._zoomMode != ZoomMode.Custom)
                {
                    _owner.RenderCurrentPage();
                }
                else
                {
                    CenterPageView();
                }
            };
            MouseWheel += OnMouseWheel;
        }

        public bool CopySelection() => _pageView.CopySelection();

        public void SetPage(Bitmap? bitmap, float zoom, List<TextChar> chars)
        {
            _pageView.SetContent(bitmap, zoom, chars);
            if (bitmap is null)
            {
                _pageView.Size = new Size(0, 0);
                AutoScrollMinSize = new Size(0, 0);
                return;
            }
            _pageView.Size = new Size(bitmap.Width + 64, bitmap.Height + 64);
            AutoScrollMinSize = new Size(bitmap.Width + 64, bitmap.Height + 64);
            CenterPageView();
        }

        private void CenterPageView()
        {
            int x = Math.Max(0, (ClientSize.Width - _pageView.Width) / 2);
            int y = Math.Max(0, (ClientSize.Height - _pageView.Height) / 2);
            _pageView.Location = new System.Drawing.Point(x, y);
        }

        private void OnMouseWheel(object? sender, MouseEventArgs e)
        {
            if ((ModifierKeys & Keys.Control) != 0)
            {
                _owner._zoomMode = ZoomMode.Custom;
                _owner._zoom = Math.Clamp(_owner._zoom + (e.Delta > 0 ? 0.1f : -0.1f),
                    MinZoom, MaxZoom);
                _owner.RenderCurrentPage();
                ((HandledMouseEventArgs)e).Handled = true;
            }
            else
            {
                ((HandledMouseEventArgs)e).Handled = false;
            }
        }
    }

    private sealed class PageView : Control
    {
        private readonly ViewerForm _owner;
        private Bitmap? _bitmap;
        private float _zoom = 1f;
        private IReadOnlyList<TextChar> _chars = Array.Empty<TextChar>();
        private PointF? _anchor;
        private PointF? _current;
        private bool _dragging;

        public PageView(ViewerForm owner)
        {
            _owner = owner;
            BackColor = System.Drawing.Color.FromArgb(66, 67, 70);
            DoubleBuffered = true;
            SetStyle(ControlStyles.ResizeRedraw, true);
            Cursor = Cursors.IBeam;
            MouseDown += OnMouseDown;
            MouseMove += OnMouseMove;
            MouseUp += OnMouseUp;
        }

        public void SetContent(Bitmap? bitmap, float zoom, List<TextChar> chars)
        {
            _bitmap = bitmap;
            _zoom = zoom;
            _chars = chars;
            _anchor = null;
            _current = null;
            Invalidate();
        }

        public bool CopySelection()
        {
            if (_anchor is not { } a || _current is not { } c)
            {
                return false;
            }
            string? text = _owner.GetSelectionText(a, c);
            if (string.IsNullOrEmpty(text))
            {
                return false;
            }
            System.Windows.Forms.Clipboard.SetText(text);
            return true;
        }

        private void OnMouseDown(object? sender, MouseEventArgs e)
        {
            if (e.Button != MouseButtons.Left || _bitmap is null)
            {
                return;
            }
            _anchor = ToPage(e.Location);
            _current = _anchor;
            _dragging = true;
            Capture = true;
            Invalidate();
        }

        private void OnMouseMove(object? sender, MouseEventArgs e)
        {
            if (!_dragging || _bitmap is null)
            {
                return;
            }
            _current = ToPage(e.Location);
            Invalidate();
        }

        private void OnMouseUp(object? sender, MouseEventArgs e)
        {
            if (!_dragging || e.Button != MouseButtons.Left)
            {
                return;
            }
            _dragging = false;
            Capture = false;
            if (_bitmap is not null)
            {
                _current = ToPage(e.Location);
                Invalidate();
            }
        }

        private PointF ToPage(System.Drawing.Point screen)
        {
            if (_bitmap is null)
            {
                return default;
            }
            float ox = Math.Max(0, (Width - _bitmap.Width) / 2f);
            float oy = Math.Max(0, (Height - _bitmap.Height) / 2f);
            return new PointF((screen.X - ox) / _zoom, (screen.Y - oy) / _zoom);
        }

        private RectangleF SelectionRect()
        {
            if (_anchor is not { } a || _current is not { } c)
            {
                return RectangleF.Empty;
            }
            float x0 = Math.Min(a.X, c.X);
            float y0 = Math.Min(a.Y, c.Y);
            float x1 = Math.Max(a.X, c.X);
            float y1 = Math.Max(a.Y, c.Y);
            return new RectangleF(x0, y0, x1 - x0, y1 - y0);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            e.Graphics.Clear(BackColor);
            if (_bitmap is null)
            {
                return;
            }
            int ox = Math.Max(0, (Width - _bitmap.Width) / 2);
            int oy = Math.Max(0, (Height - _bitmap.Height) / 2);
            e.Graphics.InterpolationMode =
                System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
            e.Graphics.DrawImage(_bitmap, ox, oy);

            RectangleF sel = SelectionRect();
            if (sel.IsEmpty)
            {
                return;
            }
            using var highlight = new SolidBrush(System.Drawing.Color.FromArgb(90, 66, 133, 244));
            using var outline = new Pen(System.Drawing.Color.FromArgb(160, 66, 133, 244));
            foreach (TextChar tc in _chars)
            {
                if (tc.X1 < sel.Left || tc.X0 > sel.Right ||
                    tc.Y1 < sel.Top || tc.Y0 > sel.Bottom)
                {
                    continue;
                }
                RectangleF r = new(
                    tc.X0 * _zoom + ox,
                    tc.Y0 * _zoom + oy,
                    (tc.X1 - tc.X0) * _zoom,
                    (tc.Y1 - tc.Y0) * _zoom);
                e.Graphics.FillRectangle(highlight, r);
                e.Graphics.DrawRectangle(outline, r.X, r.Y, r.Width, r.Height);
            }
        }
    }
}
