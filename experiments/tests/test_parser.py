import tempfile
import unittest
from pathlib import Path

from experiments.scripts.parse_results import parse_perf


class ParsePerfTests(unittest.TestCase):
    def test_parses_current_llama_cpp_perf_summary(self):
        output = """\
llama_perf_context_print:
load time = 1,234.56 ms
prompt eval time = 250.00 ms
prompt eval tokens = 10 tokens
prompt eval rate = 40.00 tokens/s
eval time = 2,000.00 ms
eval tokens = 20 tokens
eval rate = 10.00 tok/s
"""
        with tempfile.TemporaryDirectory() as directory:
            result_path = Path(directory) / "result.txt"
            result_path.write_text(output, encoding="utf-8")
            parsed = parse_perf(result_path)

        self.assertNotEqual(parsed["prompt_eval_tps"], "")
        self.assertNotEqual(parsed["decode_tps"], "")
        self.assertNotEqual(parsed["model_load_time"], "")
        self.assertEqual(parsed["prompt_eval_tps"], "40.0")
        self.assertEqual(parsed["decode_tps"], "10.0")
        self.assertEqual(parsed["model_load_time"], "1.235")
        self.assertEqual(parsed["prompt_tokens"], "10.0")
        self.assertEqual(parsed["generated_tokens"], "20.0")

    def test_parses_perf_context_counters_in_any_order(self):
        output = """\
llama_perf_context_print:
t_d_eval_ms = 2,000.00
n_d_eval = 20
t_p_eval_ms = 250.00
n_p_eval = 10
"""
        with tempfile.TemporaryDirectory() as directory:
            result_path = Path(directory) / "result.txt"
            result_path.write_text(output, encoding="utf-8")
            parsed = parse_perf(result_path)

        self.assertEqual(parsed["prompt_tokens"], "10.0")
        self.assertEqual(parsed["generated_tokens"], "20.0")
        self.assertEqual(parsed["prompt_eval_tps"], "40.0")
        self.assertEqual(parsed["decode_tps"], "10.0")


if __name__ == "__main__":
    unittest.main()
