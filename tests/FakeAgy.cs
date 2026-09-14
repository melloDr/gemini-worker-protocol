using System;

public static class FakeAgy
{
    public static void Main()
    {
        Console.WriteLine("{\"event\":\"init\",\"init\":{}}");
        Console.Out.Flush();

        string line;
        var turn = 0;
        while ((line = Console.ReadLine()) != null)
        {
            turn++;
            Console.WriteLine("{\"event\":\"step_update\",\"step_update\":{\"step_type\":\"tool\",\"tool_info\":{\"output\":\"TOP_SECRET\"}}}");

            if (line.Contains("FORCE_ERROR"))
            {
                Console.WriteLine("{\"event\":\"result\",\"result\":{\"status\":\"ERROR\",\"error\":\"timeout from fake agy\"}}");
            }
            else
            {
                Console.WriteLine("{\"event\":\"result\",\"result\":{\"status\":\"SUCCESS\",\"structured_output\":{\"status\":\"DONE\",\"task_completed\":\"fake\",\"files_read\":[],\"files_changed\":[],\"commands_run\":[],\"test_results\":[],\"assumptions\":[],\"remaining_issues\":[],\"question\":\"\",\"options\":[],\"current_state\":\"fake\"}}}");
            }
            Console.Out.Flush();
        }
    }
}
