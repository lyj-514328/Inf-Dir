package infdir.projectview;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import org.mpxj.ProjectFile;
import org.mpxj.Relation;
import org.mpxj.Task;
import org.mpxj.mpx.MPXReader;
import org.mpxj.reader.UniversalProjectReader;

/** Converts an MPXJ project into the small, stable model consumed by the viewer. */
public final class ProjectParser {
    private static final int SCHEMA_VERSION = 1;
    private static final DateTimeFormatter DATE_FORMAT = DateTimeFormatter.ISO_LOCAL_DATE_TIME;

    private ProjectParser() {}

    public static void main(String[] args) {
        try {
            if (args.length == 1 && args[0].equals("--self-test")) {
                selfTest();
                return;
            }
            Path input = parseInput(args);
            System.out.println(toJson(load(input)));
        } catch (Exception exception) {
            System.err.println("[project-parser] " + exception.getMessage());
            System.exit(1);
        }
    }

    private static Path parseInput(String[] args) {
        Path input = null;
        for (int i = 0; i < args.length; i++) {
            if (args[i].equals("--input") && i + 1 < args.length && input == null) {
                input = Path.of(args[++i]);
            } else {
                throw new IllegalArgumentException("usage: project-parser --input <FILE> | --self-test");
            }
        }
        if (input == null || !Files.isRegularFile(input)) {
            throw new IllegalArgumentException("input file does not exist: " + input);
        }
        return input.toAbsolutePath().normalize();
    }

    static ProjectData load(Path path) throws Exception {
        String extension = extension(path);
        ProjectFile project = extension.equals("mpx")
                ? new MPXReader().read(path.toString())
                : new UniversalProjectReader().read(path.toString());
        if (project == null) throw new IOException("MPXJ returned no project data");

        String title = project.getProjectProperties() == null
                ? ""
                : value(project.getProjectProperties().getProjectTitle());
        if (title.isBlank()) title = stripExtension(path.getFileName().toString());

        List<TaskData> tasks = new ArrayList<>();
        for (Task task : project.getTasks()) {
            String name = value(task.getName());
            if (name.isBlank()) continue;
            Task parent = task.getParentTask();
            List<DependencyData> dependencies = new ArrayList<>();
            for (Relation relation : task.getPredecessors()) {
                Task predecessor = relation.getPredecessorTask();
                if (predecessor != null) {
                    dependencies.add(new DependencyData(
                            integerText(predecessor.getUniqueID(), predecessor.getID()),
                            value(relation.getType()),
                            value(relation.getLag())));
                }
            }
            tasks.add(new TaskData(
                    integerText(task.getID(), task.getUniqueID()),
                    integerText(task.getUniqueID(), task.getID()),
                    parent == null ? null : integerText(parent.getUniqueID(), parent.getID()),
                    value(task.getWBS()),
                    name,
                    task.getOutlineLevel() == null ? 1 : task.getOutlineLevel(),
                    date(task.getStart()),
                    date(task.getFinish()),
                    value(task.getDurationText(), task.getDuration()),
                    number(task.getPercentageComplete()),
                    task.getSummary(),
                    task.getMilestone(),
                    dependencies));
        }
        return new ProjectData(SCHEMA_VERSION, path.getFileName().toString(), title, tasks);
    }

    private static void selfTest() throws Exception {
        Path directory = Files.createTempDirectory("inf-dir-project-parser-");
        Path file = directory.resolve("self-test.mpx");
        String mpx = """
                MPX,Microsoft Project for Windows,4.0,ANSI
                10,$,1,2,",",.
                11,2,0,1,8.00,40.00,,,1,0
                12,1,0,480,/,:,am,pm,20,20
                30,Inf-Dir self-test,,,,,,0,01/01/2026,,,,,,,,,,,,,,,,,0d,0d
                60,Name,WBS,Outline Level,Fixed,ID,Unique ID,Outline Number
                61,1,2,3,80,90,98,99
                70,Preview task,1,1,No,1,1,1
                """;
        Files.writeString(file, mpx, StandardCharsets.US_ASCII);
        ProjectData data = load(file);
        if (!data.title().equals("Inf-Dir self-test") || data.tasks().stream().noneMatch(t -> t.name().equals("Preview task"))) {
            throw new IllegalStateException("MPXJ self-test did not round-trip the project");
        }
        Files.deleteIfExists(file);
        Files.deleteIfExists(directory);
    }

    private static String toJson(ProjectData data) {
        Json json = new Json();
        json.objectStart();
        json.field("schemaVersion", data.schemaVersion());
        json.field("fileName", data.fileName());
        json.field("title", data.title());
        json.name("tasks").arrayStart();
        for (TaskData task : data.tasks()) {
            json.objectStart();
            json.field("id", task.id());
            json.field("uid", task.uid());
            json.field("parentId", task.parentId());
            json.field("wbs", task.wbs());
            json.field("name", task.name());
            json.field("outlineLevel", task.outlineLevel());
            json.field("start", task.start());
            json.field("finish", task.finish());
            json.field("duration", task.duration());
            json.field("percentComplete", task.percentComplete());
            json.field("summary", task.summary());
            json.field("milestone", task.milestone());
            json.name("predecessors").arrayStart();
            for (DependencyData dependency : task.dependencies()) {
                json.objectStart();
                json.field("taskId", dependency.taskId());
                json.field("type", dependency.type());
                json.field("lag", dependency.lag());
                json.objectEnd();
            }
            json.arrayEnd();
            json.objectEnd();
        }
        json.arrayEnd();
        json.name("warnings").arrayStart().arrayEnd();
        json.objectEnd();
        return json.toString();
    }

    private static String extension(Path path) {
        String name = path.getFileName().toString().toLowerCase(Locale.ROOT);
        int dot = name.lastIndexOf('.');
        return dot < 0 ? "" : name.substring(dot + 1);
    }

    private static String stripExtension(String value) {
        int dot = value.lastIndexOf('.');
        return dot > 0 ? value.substring(0, dot) : value;
    }

    private static String value(Object value) { return value == null ? "" : String.valueOf(value); }
    private static String value(Object first, Object fallback) {
        String result = value(first);
        return result.isBlank() ? value(fallback) : result;
    }
    private static String integerText(Object first, Object fallback) {
        String result = value(first);
        return result.isBlank() || result.equals("0") ? value(fallback) : result;
    }
    private static String date(LocalDateTime value) { return value == null ? null : DATE_FORMAT.format(value); }
    private static double number(Number value) { return value == null ? 0 : Math.max(0, Math.min(100, value.doubleValue())); }

    record ProjectData(int schemaVersion, String fileName, String title, List<TaskData> tasks) {}
    record TaskData(String id, String uid, String parentId, String wbs, String name, int outlineLevel,
                    String start, String finish, String duration, double percentComplete,
                    boolean summary, boolean milestone, List<DependencyData> dependencies) {}
    record DependencyData(String taskId, String type, String lag) {}

    private static final class Json {
        private final StringBuilder out = new StringBuilder();
        private final List<Boolean> first = new ArrayList<>();
        private boolean afterName;

        Json objectStart() { valuePrefix(); out.append('{'); first.add(true); return this; }
        Json objectEnd() { out.append('}'); first.remove(first.size() - 1); afterName = false; return this; }
        Json arrayStart() { valuePrefix(); out.append('['); first.add(true); return this; }
        Json arrayEnd() { out.append(']'); first.remove(first.size() - 1); afterName = false; return this; }
        Json name(String name) { valuePrefix(); string(name); out.append(':'); afterName = true; return this; }
        Json field(String name, String value) { name(name); nullable(value); return this; }
        Json field(String name, int value) { name(name); out.append(value); afterName = false; return this; }
        Json field(String name, double value) { name(name); out.append(String.format(Locale.ROOT, "%.2f", value)); afterName = false; return this; }
        Json field(String name, boolean value) { name(name); out.append(value); afterName = false; return this; }
        private void nullable(String value) { if (value == null) out.append("null"); else string(value); afterName = false; }
        private void string(String value) {
            out.append('"');
            for (int i = 0; i < value.length(); i++) {
                char c = value.charAt(i);
                switch (c) {
                    case '\\' -> out.append("\\\\");
                    case '"' -> out.append("\\\"");
                    case '\n' -> out.append("\\n");
                    case '\r' -> out.append("\\r");
                    case '\t' -> out.append("\\t");
                    default -> { if (c < 0x20) out.append(String.format(Locale.ROOT, "\\u%04x", (int) c)); else out.append(c); }
                }
            }
            out.append('"');
        }
        private void valuePrefix() {
            if (afterName) return;
            if (!first.isEmpty()) {
                int last = first.size() - 1;
                if (first.get(last)) first.set(last, false); else out.append(',');
            }
        }
        @Override public String toString() { return out.toString(); }
    }
}
