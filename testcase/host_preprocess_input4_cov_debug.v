task run_test;
begin
  if (!$value$plusargs("INPUT_FILE=%s", input_file_name))
    input_file_name = "input1.txt";
  if ($value$plusargs("CASE_NAME=%s", input_file_name))
    $display("Test_result STARTED %0s", input_file_name);
  if (!$value$plusargs("INPUT_FILE=%s", input_file_name))
    input_file_name = "input1.txt";
  $display("# TEST_INPUT=%0s", input_file_name);
  run_selected_test();
end
endtask
