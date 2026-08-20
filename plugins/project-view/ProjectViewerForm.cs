using System.ComponentModel;

namespace InfDir.ProjectView;

internal sealed class ProjectViewerForm : Form
{
    private readonly ProjectModel _model;
    private readonly DataGridView _grid = new();
    private readonly TimelinePanel _timeline;

    public ProjectViewerForm(ProjectModel model, WindowPlacement? placement)
    {
        _model = model;
        _timeline = new TimelinePanel(model.Tasks);
        Text = $"{model.FileName} - Project 查看器";
        MinimumSize = new Size(680, 420);
        StartPosition = placement is null ? FormStartPosition.CenterScreen : FormStartPosition.Manual;
        ClientSize = new Size(1100, 760);
        KeyPreview = true;

        var header = new Panel { Dock = DockStyle.Top, Height = 62, Padding = new Padding(16, 9, 16, 6) };
        header.Controls.Add(new Label
        {
            Text = $"{model.Title}\r\n{model.Tasks.Count} 个任务",
            Dock = DockStyle.Fill,
            AutoEllipsis = true,
            Font = new Font(SystemFonts.MessageBoxFont?.FontFamily ?? FontFamily.GenericSansSerif, 11, FontStyle.Bold),
        });

        ConfigureGrid();
        var split = new SplitContainer
        {
            Dock = DockStyle.Fill,
            Orientation = Orientation.Vertical,
            SplitterDistance = 620,
            Panel1MinSize = 420,
            Panel2MinSize = 220,
        };
        split.Panel1.Controls.Add(_grid);
        split.Panel2.Controls.Add(_timeline);
        Controls.Add(split);
        Controls.Add(header);

        ApplyPlacement(placement);
        KeyDown += (_, eventArgs) =>
        {
            if (eventArgs.KeyCode == Keys.Escape) Close();
            if (eventArgs.Control && eventArgs.KeyCode == Keys.C && _grid.GetCellCount(DataGridViewElementStates.Selected) > 0)
            {
                DataObject? clipboard = _grid.GetClipboardContent();
                if (clipboard is not null)
                {
                    Clipboard.SetDataObject(clipboard);
                    eventArgs.Handled = true;
                }
            }
        };
        _grid.Scroll += (_, _) => _timeline.VerticalOffset = _grid.FirstDisplayedScrollingRowIndex;
    }

    private void ConfigureGrid()
    {
        _grid.Dock = DockStyle.Fill;
        _grid.ReadOnly = true;
        _grid.AllowUserToAddRows = false;
        _grid.AllowUserToDeleteRows = false;
        _grid.AllowUserToResizeRows = false;
        _grid.RowHeadersVisible = false;
        _grid.SelectionMode = DataGridViewSelectionMode.FullRowSelect;
        _grid.AutoGenerateColumns = false;
        _grid.ClipboardCopyMode = DataGridViewClipboardCopyMode.EnableAlwaysIncludeHeaderText;
        _grid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "ID", Width = 52 });
        _grid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "任务", Width = 270 });
        _grid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "开始", Width = 100 });
        _grid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "完成", Width = 100 });
        _grid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "工期", Width = 92 });
        _grid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "进度", Width = 68 });
        foreach (ProjectTask task in _model.Tasks)
        {
            int row = _grid.Rows.Add(
                task.Id,
                new string(' ', Math.Max(0, task.OutlineLevel - 1) * 3) + task.Name,
                task.Start?.ToString("yyyy-MM-dd") ?? "",
                task.Finish?.ToString("yyyy-MM-dd") ?? "",
                task.Duration,
                $"{task.PercentComplete:F0}%");
            if (task.Summary)
            {
                _grid.Rows[row].DefaultCellStyle.Font = new Font(_grid.Font, FontStyle.Bold);
            }
        }
    }

    private void ApplyPlacement(WindowPlacement? placement)
    {
        if (placement is null) return;
        Location = new Point(placement.X, placement.Y);
        ClientSize = new Size(placement.ClientWidth, placement.ClientHeight);
        if (placement.Maximized) WindowState = FormWindowState.Maximized;
    }

    private sealed class TimelinePanel : Panel
    {
        private const int RowHeight = 22;
        private readonly IReadOnlyList<ProjectTask> _tasks;
        private readonly DateTime _start;
        private readonly int _days;
        private int _verticalOffset;

        public TimelinePanel(IReadOnlyList<ProjectTask> tasks)
        {
            _tasks = tasks;
            DoubleBuffered = true;
            Dock = DockStyle.Fill;
            BackColor = Color.White;
            DateTime? start = tasks.Where(task => task.Start.HasValue).Min(task => task.Start);
            DateTime? finish = tasks.Where(task => task.Finish.HasValue).Max(task => task.Finish);
            _start = start?.Date ?? DateTime.Today;
            _days = Math.Max(1, (int)Math.Ceiling(((finish ?? _start.AddDays(1)) - _start).TotalDays));
        }

        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        public int VerticalOffset
        {
            get => _verticalOffset;
            set { _verticalOffset = Math.Max(0, value); Invalidate(); }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            int headerHeight = 28;
            using var gridPen = new Pen(Color.FromArgb(230, 232, 235));
            using var barBrush = new SolidBrush(Color.FromArgb(56, 132, 255));
            using var progressBrush = new SolidBrush(Color.FromArgb(23, 92, 181));
            using var summaryBrush = new SolidBrush(Color.FromArgb(45, 55, 72));
            e.Graphics.DrawString($"{_start:yyyy-MM-dd}  -  {_start.AddDays(_days):yyyy-MM-dd}", Font, Brushes.DimGray, 8, 6);
            double pixelsPerDay = Math.Max(1d, (ClientSize.Width - 12d) / _days);
            int visibleRows = Math.Max(0, (ClientSize.Height - headerHeight) / RowHeight + 1);
            for (int visible = 0; visible < visibleRows; visible++)
            {
                int index = _verticalOffset + visible;
                if (index >= _tasks.Count) break;
                int y = headerHeight + visible * RowHeight;
                e.Graphics.DrawLine(gridPen, 0, y + RowHeight - 1, ClientSize.Width, y + RowHeight - 1);
                ProjectTask task = _tasks[index];
                if (task.Start is not { } start || task.Finish is not { } finish) continue;
                int x = 6 + (int)Math.Round((start.Date - _start).TotalDays * pixelsPerDay);
                int width = Math.Max(3, (int)Math.Round(Math.Max(1, (finish.Date - start.Date).TotalDays + 1) * pixelsPerDay));
                var bar = new Rectangle(x, y + 5, width, 12);
                e.Graphics.FillRectangle(task.Summary ? summaryBrush : barBrush, bar);
                int progressWidth = (int)Math.Round(width * Math.Clamp(task.PercentComplete, 0, 100) / 100d);
                if (progressWidth > 0) e.Graphics.FillRectangle(progressBrush, x, y + 13, progressWidth, 4);
                if (task.Milestone)
                {
                    Point center = new(x + width, y + 11);
                    e.Graphics.FillPolygon(summaryBrush, new[]
                    {
                        new Point(center.X, center.Y - 6), new Point(center.X + 6, center.Y),
                        new Point(center.X, center.Y + 6), new Point(center.X - 6, center.Y),
                    });
                }
            }
        }
    }
}
