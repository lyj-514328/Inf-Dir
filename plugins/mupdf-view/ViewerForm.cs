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

    private enum ZoomMode
    {
        FitWidth,
        FitPage,
        Custom,
    }

    public ViewerForm(string file, WindowPlacement? placement)
    {
        _fileName = Path.GetFileName(file);
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

        _toolbar.BackColorChanged += (_, _) => { };
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

    private Bitmap? _pageBitmap;

    private void RenderCurrentPage()
    {
        try
        {
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
            }
            _canvas.SetPage(_pageBitmap, _zoom);
            UpdatePageControls();
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, $"渲染失败：{ex.Message}", "MuPDF 查看器",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
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
            _pageView = new PageView();
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

        public void SetPage(Bitmap? bitmap, float zoom)
        {
            _pageView.SetBitmap(bitmap);
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
        private Bitmap? _bitmap;

        public PageView()
        {
            BackColor = System.Drawing.Color.FromArgb(66, 67, 70);
            DoubleBuffered = true;
            SetStyle(ControlStyles.ResizeRedraw, true);
        }

        public void SetBitmap(Bitmap? bitmap)
        {
            _bitmap = bitmap;
            Invalidate();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            e.Graphics.Clear(BackColor);
            if (_bitmap is null)
            {
                return;
            }
            int x = Math.Max(0, (Width - _bitmap.Width) / 2);
            int y = Math.Max(0, (Height - _bitmap.Height) / 2);
            e.Graphics.InterpolationMode =
                System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
            e.Graphics.DrawImage(_bitmap, x, y);
        }
    }
}
