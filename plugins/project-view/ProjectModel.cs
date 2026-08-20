using MPXJ.Net;
using System.Text;

namespace InfDir.ProjectView;

internal sealed record ProjectTask(
    string Id,
    string Name,
    int OutlineLevel,
    DateTime? Start,
    DateTime? Finish,
    string Duration,
    double PercentComplete,
    bool Summary,
    bool Milestone);

internal sealed record ProjectModel(string FileName, string Title, IReadOnlyList<ProjectTask> Tasks)
{
    public static void SelfTest()
    {
        string temp = Path.Combine(Path.GetTempPath(), "Inf-Dir", "project-view-self-test", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(temp);
        try
        {
            string path = Path.Combine(temp, "self-test.mpx");
            const string mpx = """
MPX,Microsoft Project for Windows,4.0,ANSI
10,$,1,2,",",.
11,2,0,1,8.00,40.00,,,1,0
12,1,0,480,/,:,am,pm,20,20
30,Inf-Dir self-test,,,,,,0,01/01/2026,,,,,,,,,,,,,,,,,0d,0d
60,Name,WBS,Outline Level,Fixed,ID,Unique ID,Outline Number
61,1,2,3,80,90,98,99
70,Preview task,1,1,No,1,1,1
""";
            File.WriteAllText(path, mpx, Encoding.ASCII);
            ProjectModel model = Load(path);
            if (model.Title != "Inf-Dir self-test" || model.Tasks.All(task => task.Name != "Preview task"))
            {
                throw new InvalidDataException("MPXJ self-test did not round-trip the project.");
            }
        }
        finally
        {
            GC.Collect();
            GC.WaitForPendingFinalizers();
            try { Directory.Delete(temp, recursive: true); }
            catch (IOException) { }
        }
    }

    public static ProjectModel Load(string path)
    {
        dynamic project = (Path.GetExtension(path).Equals(".mpx", StringComparison.OrdinalIgnoreCase)
                ? new MPXReader().Read(path)
                : new UniversalProjectReader().Read(path))
            ?? throw new InvalidDataException("MPXJ 没有返回工程数据。");
        var tasks = new List<ProjectTask>();
        foreach (dynamic task in project.Tasks)
        {
            string name = Text(task.Name);
            if (string.IsNullOrWhiteSpace(name))
            {
                continue;
            }
            tasks.Add(new ProjectTask(
                Text(task.ID),
                name,
                Integer(task.OutlineLevel, 1),
                Date(task.Start),
                Date(task.Finish),
                Text(task.Duration),
                Number(task.PercentageComplete),
                Boolean(task.Summary),
                Boolean(task.Milestone)));
        }

        string title = string.Empty;
        try
        {
            title = Text(project.ProjectProperties.ProjectTitle);
        }
        catch
        {
            // Some interchange formats have no project properties section.
        }
        if (string.IsNullOrWhiteSpace(title))
        {
            title = Path.GetFileNameWithoutExtension(path);
        }
        return new ProjectModel(Path.GetFileName(path), title, tasks);
    }

    private static string Text(dynamic? value) => value is null ? string.Empty : Convert.ToString(value) ?? string.Empty;

    private static int Integer(dynamic? value, int fallback)
    {
        try { return value is null ? fallback : Convert.ToInt32(value); }
        catch { return fallback; }
    }

    private static double Number(dynamic? value)
    {
        try { return value is null ? 0 : Convert.ToDouble(value); }
        catch { return 0; }
    }

    private static bool Boolean(dynamic? value)
    {
        try { return value is not null && Convert.ToBoolean(value); }
        catch { return false; }
    }

    private static DateTime? Date(dynamic? value)
    {
        try
        {
            if (value is null) return null;
            DateTime date = Convert.ToDateTime(value);
            return date.Year <= 1 || date.Year >= 9999 ? null : date;
        }
        catch { return null; }
    }
}
