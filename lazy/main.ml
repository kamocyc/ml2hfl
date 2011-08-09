open ExtList

let infer cexs prog =
  let uid = Ctree.gen () in
  let ret, args =
    Ctree.ret_args
     (Var.V(prog.Prog.main))
     uid
     (SimType.arity (Prog.type_of prog (Var.V(prog.Prog.main))))
  in
  let init = Term.Ret([], ret, Term.Call([], Term.make_var prog.Prog.main, args)) in
  let rt = Ctree.Node((uid, []), init, ref []) in

  let strategy =
    match 0 with
      0 -> Ctree.bf_strategy rt
    | 1 -> Ctree.df_strategy rt
    | 2 -> Ctree.cex_strategy cexs rt
  in
  let eps = Ctree.manual prog rt strategy in
		let eptrs = List.map Trace.of_error_path eps in
(*
		let _ = Format.printf "error path trees:@.  @[<v>%a@]@." (Util.pr_list pr_tree "@,") eptrs in
*)
		let sums = Util.concat_map
				(fun eptr ->
      Format.printf "@.";
      Trace.summaries_of eptr)
		  eptrs
		in
  let fcs = List.unique (Util.concat_map Trace.function_calls_of eptrs) in
  let styenv = SizType.of_summaries (Prog.type_of prog) fcs sums in
		let pr ppf (f, sty) = Format.fprintf ppf "%a: %a" Var.pr f SizType.pr (SizType.alpha sty) in
		Format.printf "function summaries:@.  @[<v>%a@]@." (Util.pr_list pr "@ ") styenv

let test_sum () =
  let main = { Fdef.attr = []; Fdef.name = Idnt.make "main"; Fdef.args = [Idnt.make "n"]; Fdef.guard = Term.make_true; Fdef.body = Term.apply (Term.make_var "check") [Term.apply (Term.make_var "sum") [Term.make_var "n"]; Term.make_var "n"] } in
  let sum1 = { Fdef.attr = []; Fdef.name = Idnt.make "sum"; Fdef.args = [Idnt.make "x"]; Fdef.guard = Term.leq (Term.make_var "x") (Term.make_int 0); Fdef.body = Term.make_int 0 } in
  let sum2 = { Fdef.attr = []; Fdef.name = Idnt.make "sum"; Fdef.args = [Idnt.make "x"]; Fdef.guard = Term.gt (Term.make_var "x") (Term.make_int 0); Fdef.body = Term.add (Term.make_var "x") (Term.apply (Term.make_var "sum") [Term.sub (Term.make_var "x") (Term.make_int 1)])} in
  let check1 = { Fdef.attr = []; Fdef.name = Idnt.make "check"; Fdef.args = [Idnt.make "x1"; Idnt.make "x2"]; guard = Term.geq (Term.make_var "x1") (Term.make_var "x2"); Fdef.body = Term.make_unit} in
  let check2 = { Fdef.attr = []; Fdef.name = Idnt.make "check"; Fdef.args = [Idnt.make "x1"; Idnt.make "x2"]; guard = Term.lt (Term.make_var "x1") (Term.make_var "x2"); Fdef.body = Term.make_event "fail"} in
  let tymain = SimType.Fun(SimType.Int, SimType.Unit) in
  let tysum = SimType.Fun(SimType.Int, SimType.Int) in
  let tycheck = SimType.Fun(SimType.Int, SimType.Fun(SimType.Int, SimType.Unit)) in
  let prog = { Prog.attr = [];
               Prog.fdefs = [main; sum1; sum2; check1; check2];
               Prog.types = [Idnt.make "main", tymain; Idnt.make "sum", tysum; Idnt.make "check", tycheck];
               Prog.main = main.Fdef.name } in
  Format.printf "%a" Prog.pr prog;
  infer [] prog

let test_sum_assert () =
  let main = { Fdef.attr = []; Fdef.name = Idnt.make "main"; Fdef.args = [Idnt.make "n"]; Fdef.guard = Term.make_true; Fdef.body = Term.apply (Term.make_var "assert") [Term.geq (Term.apply (Term.make_var "sum") [Term.make_var "n"]) (Term.make_var "n")] } in
  let sum1 = { Fdef.attr = []; Fdef.name = Idnt.make "sum"; Fdef.args = [Idnt.make "x"]; Fdef.guard = Term.leq (Term.make_var "x") (Term.make_int 0); Fdef.body = Term.make_int 0 } in
  let sum2 = { Fdef.attr = []; Fdef.name = Idnt.make "sum"; Fdef.args = [Idnt.make "x"]; Fdef.guard = Term.gt (Term.make_var "x") (Term.make_int 0); Fdef.body = Term.add (Term.make_var "x") (Term.apply (Term.make_var "sum") [Term.sub (Term.make_var "x") (Term.make_int 1)])} in
  let assert1 = { Fdef.attr = []; Fdef.name = Idnt.make "assert"; Fdef.args = [Idnt.make "b"]; guard = Term.eq (Term.make_var "b") (Term.make_true); Fdef.body = Term.make_unit} in
  let assert2 = { Fdef.attr = []; Fdef.name = Idnt.make "assert"; Fdef.args = [Idnt.make "b"]; guard = Term.eq (Term.make_var "b") (Term.make_false); Fdef.body = Term.make_event "fail"} in
  let tymain = SimType.Fun(SimType.Int, SimType.Unit) in
  let tysum = SimType.Fun(SimType.Int, SimType.Int) in
  let tyassert = SimType.Fun(SimType.Bool, SimType.Unit) in
  let prog = { Prog.attr = [];
               Prog.fdefs = [main; sum1; sum2; assert1; assert2];
               Prog.types = [Idnt.make "main", tymain; Idnt.make "sum", tysum; Idnt.make "assert", tyassert];
               Prog.main = main.Fdef.name } in
  Format.printf "%a" Prog.pr prog;
  infer [] prog

let test_copy_copy () =
  let main = { Fdef.attr = []; Fdef.name = Idnt.make "main"; Fdef.args = [Idnt.make "n"]; Fdef.guard = Term.make_true; Fdef.body = Term.apply (Term.make_var "check") [Term.apply (Term.make_var "copy") [Term.apply (Term.make_var "copy") [Term.make_var "n"]]; Term.make_var "n"] } in
  let copy1 = { Fdef.attr = []; Fdef.name = Idnt.make "copy"; Fdef.args = [Idnt.make "x"]; Fdef.guard = Term.eq (Term.make_var "x") (Term.make_int 0); Fdef.body = Term.make_int 0 } in
  let copy2 = { Fdef.attr = []; Fdef.name = Idnt.make "copy"; Fdef.args = [Idnt.make "x"]; Fdef.guard = Term.neq (Term.make_var "x") (Term.make_int 0); Fdef.body = Term.add (Term.make_int 1) (Term.apply (Term.make_var "copy") [Term.sub (Term.make_var "x") (Term.make_int 1)])} in
  let check1 = { Fdef.attr = []; Fdef.name = Idnt.make "check"; Fdef.args = [Idnt.make "x1"; Idnt.make "x2"]; guard = Term.eq (Term.make_var "x1") (Term.make_var "x2"); Fdef.body = Term.make_unit} in
  let check2 = { Fdef.attr = []; Fdef.name = Idnt.make "check"; Fdef.args = [Idnt.make "x1"; Idnt.make "x2"]; guard = Term.neq (Term.make_var "x1") (Term.make_var "x2"); Fdef.body = Term.make_event "fail"} in
  let tymain = SimType.Fun(SimType.Int, SimType.Unit) in
  let tycopy = SimType.Fun(SimType.Int, SimType.Int) in
  let tycheck = SimType.Fun(SimType.Int, SimType.Fun(SimType.Int, SimType.Unit)) in
  let prog = { Prog.attr = [];
               Prog.fdefs = [main; copy1; copy2; check1; check2];
               Prog.types = [Idnt.make "main", tymain; Idnt.make "copy", tycopy; Idnt.make "check", tycheck];
               Prog.main = main.Fdef.name } in
  Format.printf "%a" Prog.pr prog;
  infer [] prog

let test_apply () =
  let main = { Fdef.attr = []; Fdef.name = Idnt.make "main"; Fdef.args = [Idnt.make "n"]; Fdef.guard = Term.make_true; Fdef.body = Term.apply (Term.make_var "apply") [Term.apply (Term.make_var "check") [Term.make_var "n"]; Term.make_var "n"] } in
  let apply = { Fdef.attr = []; Fdef.name = Idnt.make "apply"; Fdef.args = [Idnt.make "f"; Idnt.make "x"]; Fdef.guard = Term.make_true; Fdef.body = Term.apply (Term.make_var "f") [Term.make_var "x"] } in
  let check1 = { Fdef.attr = []; Fdef.name = Idnt.make "check"; Fdef.args = [Idnt.make "x1"; Idnt.make "x2"]; guard = Term.eq (Term.make_var "x1") (Term.make_var "x2"); Fdef.body = Term.make_unit} in
  let check2 = { Fdef.attr = []; Fdef.name = Idnt.make "check"; Fdef.args = [Idnt.make "x1"; Idnt.make "x2"]; guard = Term.neq (Term.make_var "x1") (Term.make_var "x2"); Fdef.body = Term.make_event "fail"} in
  let tymain = SimType.Fun(SimType.Int, SimType.Unit) in
  let tyapply = SimType.Fun(SimType.Fun(SimType.Int, SimType.Unit), SimType.Fun(SimType.Int, SimType.Unit)) in
  let tycheck = SimType.Fun(SimType.Int, SimType.Fun(SimType.Int, SimType.Unit)) in
  let prog = { Prog.attr = [];
               Prog.fdefs = [main; apply; check1; check2];
               Prog.types = [Idnt.make "main", tymain; Idnt.make "apply", tyapply; Idnt.make "check", tycheck];
               Prog.main = main.Fdef.name } in
  Format.printf "%a" Prog.pr prog;
  infer [] prog

let test_bar_hoge () =
  let main = { Fdef.attr = []; Fdef.name = Idnt.make "main"; Fdef.args = [Idnt.make "n"]; Fdef.guard = Term.make_true; Fdef.body = Term.apply (Term.make_var "bar") [Term.apply (Term.make_var "hoge") [Term.make_var "n"]; Term.make_var "n"] } in
  let bar = { Fdef.attr = []; Fdef.name = Idnt.make "bar"; Fdef.args = [Idnt.make "f"; Idnt.make "x"]; Fdef.guard = Term.make_true; Fdef.body = Term.apply (Term.make_var "f") [Term.make_var "x"; Term.make_var "check"] } in
  let hoge = { Fdef.attr = []; Fdef.name = Idnt.make "hoge"; Fdef.args = [Idnt.make "x"; Idnt.make "y"; Idnt.make "f"]; Fdef.guard = Term.make_true; Fdef.body = Term.apply (Term.make_var "f") [Term.make_var "x"; Term.make_var "y"] } in
  let check1 = { Fdef.attr = []; Fdef.name = Idnt.make "check"; Fdef.args = [Idnt.make "x1"; Idnt.make "x2"]; guard = Term.eq (Term.make_var "x1") (Term.make_var "x2"); Fdef.body = Term.make_unit} in
  let check2 = { Fdef.attr = []; Fdef.name = Idnt.make "check"; Fdef.args = [Idnt.make "x1"; Idnt.make "x2"]; guard = Term.neq (Term.make_var "x1") (Term.make_var "x2"); Fdef.body = Term.make_event "fail"} in
  let tymain = SimType.Fun(SimType.Int, SimType.Unit) in
  let tybar = SimType.Fun(SimType.Fun(SimType.Int, SimType.Fun(SimType.Fun(SimType.Int, SimType.Fun(SimType.Int, SimType.Unit)), SimType.Unit)), SimType.Fun(SimType.Int, SimType.Unit)) in
  let tyhoge = SimType.Fun(SimType.Int, SimType.Fun(SimType.Int, SimType.Fun(SimType.Fun(SimType.Int, SimType.Fun(SimType.Int, SimType.Unit)), SimType.Unit))) in
  let tycheck = SimType.Fun(SimType.Int, SimType.Fun(SimType.Int, SimType.Unit)) in
  let prog = { Prog.attr = [];
               Prog.fdefs = [main; bar; hoge; check1; check2];
               Prog.types = [Idnt.make "main", tymain; Idnt.make "bar", tybar; Idnt.make "hoge", tyhoge; Idnt.make "check", tycheck];
               Prog.main = main.Fdef.name } in
  Format.printf "%a" Prog.pr prog;
  infer [] prog

let test_checkh () =
  let main = { Fdef.attr = []; Fdef.name = Idnt.make "main"; Fdef.args = [Idnt.make "n"]; Fdef.guard = Term.make_true; Fdef.body = Term.apply (Term.make_var "checkh") [Term.apply (Term.make_var "h") [Term.make_var "n"]; Term.apply (Term.make_var "h") [Term.make_var "n"]] } in
  let checkh = { Fdef.attr = []; Fdef.name = Idnt.make "checkh"; Fdef.args = [Idnt.make "f"; Idnt.make "g"]; Fdef.guard = Term.make_true; Fdef.body = Term.apply (Term.make_var "check") [Term.apply (Term.make_var "f") [Term.make_unit]; Term.apply (Term.make_var "g") [Term.make_unit]] } in
  let check1 = { Fdef.attr = []; Fdef.name = Idnt.make "check"; Fdef.args = [Idnt.make "x1"; Idnt.make "x2"]; guard = Term.eq (Term.make_var "x1") (Term.make_var "x2"); Fdef.body = Term.make_unit} in
  let check2 = { Fdef.attr = []; Fdef.name = Idnt.make "check"; Fdef.args = [Idnt.make "x1"; Idnt.make "x2"]; guard = Term.neq (Term.make_var "x1") (Term.make_var "x2"); Fdef.body = Term.make_event "fail"} in
  let h = { Fdef.attr = []; Fdef.name = Idnt.make "h"; Fdef.args = [Idnt.make "x"; Idnt.make "un"]; guard = Term.make_true; Fdef.body = Term.make_var "x"} in
  let tymain = SimType.Fun(SimType.Int, SimType.Unit) in
  let tycheckh = SimType.Fun(SimType.Fun(SimType.Unit, SimType.Int), SimType.Fun(SimType.Fun(SimType.Unit, SimType.Int), SimType.Unit)) in
  let tycheck = SimType.Fun(SimType.Int, SimType.Fun(SimType.Int, SimType.Unit)) in
  let tyh = SimType.Fun(SimType.Int, SimType.Fun(SimType.Unit, SimType.Int)) in
  let prog = { Prog.attr = [];
               Prog.fdefs = [main; checkh; check1; check2; h];
               Prog.types = [Idnt.make "main", tymain; Idnt.make "checkh", tycheckh; Idnt.make "check", tycheck; Idnt.make "h", tyh];
               Prog.main = main.Fdef.name } in
  Format.printf "%a" Prog.pr prog;
  infer [] prog

let test_applyh () =
  let main = { Fdef.attr = []; Fdef.name = Idnt.make "main"; Fdef.args = [Idnt.make "n"]; Fdef.guard = Term.make_true; Fdef.body = Term.apply (Term.make_var "applyh") [Term.make_var "apply"; Term.make_var "check"; Term.make_var "n"] } in
  let applyh = { Fdef.attr = []; Fdef.name = Idnt.make "applyh"; Fdef.args = [Idnt.make "f"; Idnt.make "g"; Idnt.make "x"]; Fdef.guard = Term.make_true; Fdef.body = Term.apply (Term.make_var "f") [Term.apply (Term.make_var "g") [Term.make_var "x"]; Term.make_var "x"] } in
  let apply = { Fdef.attr = []; Fdef.name = Idnt.make "apply"; Fdef.args = [Idnt.make "f"; Idnt.make "x"]; Fdef.guard = Term.make_true; Fdef.body = Term.apply (Term.make_var "f") [Term.make_var "x"] } in
  let check1 = { Fdef.attr = []; Fdef.name = Idnt.make "check"; Fdef.args = [Idnt.make "x1"; Idnt.make "x2"]; guard = Term.eq (Term.make_var "x1") (Term.make_var "x2"); Fdef.body = Term.make_unit} in
  let check2 = { Fdef.attr = []; Fdef.name = Idnt.make "check"; Fdef.args = [Idnt.make "x1"; Idnt.make "x2"]; guard = Term.neq (Term.make_var "x1") (Term.make_var "x2"); Fdef.body = Term.make_event "fail"} in
  let tymain = SimType.Fun(SimType.Int, SimType.Unit) in
  let tyapplyh = SimType.Fun
    (SimType.Fun
      (SimType.Fun(SimType.Int, SimType.Unit),
      SimType.Fun(SimType.Int, SimType.Unit)),
    SimType.Fun
      (SimType.Fun(SimType.Int, SimType.Fun(SimType.Int, SimType.Unit)),
      SimType.Fun(SimType.Int, SimType.Unit))) in
  let tyapply = SimType.Fun(SimType.Fun(SimType.Int, SimType.Unit), SimType.Fun(SimType.Int, SimType.Unit)) in
  let tycheck = SimType.Fun(SimType.Int, SimType.Fun(SimType.Int, SimType.Unit)) in
  let prog = { Prog.attr = [];
               Prog.fdefs = [main; applyh; apply; check1; check2];
               Prog.types = [Idnt.make "main", tymain; Idnt.make "applyh", tyapplyh; Idnt.make "apply", tyapply; Idnt.make "check", tycheck];
               Prog.main = main.Fdef.name } in
  Format.printf "%a" Prog.pr prog;
  infer [] prog

let test_applyh2 () =
  let main = { Fdef.attr = []; Fdef.name = Idnt.make "main"; Fdef.args = [Idnt.make "n"]; Fdef.guard = Term.make_true; Fdef.body = Term.apply (Term.make_var "applyh") [Term.make_var "apply"; Term.apply (Term.make_var "check") [Term.make_var "n"]; Term.make_var "n"] } in
  let applyh = { Fdef.attr = []; Fdef.name = Idnt.make "applyh"; Fdef.args = [Idnt.make "f"; Idnt.make "g"; Idnt.make "x"]; Fdef.guard = Term.make_true; Fdef.body = Term.apply (Term.make_var "f") [Term.make_var "g"; Term.make_var "x"] } in
  let apply = { Fdef.attr = []; Fdef.name = Idnt.make "apply"; Fdef.args = [Idnt.make "f"; Idnt.make "x"]; Fdef.guard = Term.make_true; Fdef.body = Term.apply (Term.make_var "f") [Term.make_var "x"] } in
  let check1 = { Fdef.attr = []; Fdef.name = Idnt.make "check"; Fdef.args = [Idnt.make "x1"; Idnt.make "x2"]; guard = Term.eq (Term.make_var "x1") (Term.make_var "x2"); Fdef.body = Term.make_unit} in
  let check2 = { Fdef.attr = []; Fdef.name = Idnt.make "check"; Fdef.args = [Idnt.make "x1"; Idnt.make "x2"]; guard = Term.neq (Term.make_var "x1") (Term.make_var "x2"); Fdef.body = Term.make_event "fail"} in
  let tymain = SimType.Fun(SimType.Int, SimType.Unit) in
  let tyapplyh = SimType.Fun
    (SimType.Fun
      (SimType.Fun(SimType.Int, SimType.Unit),
      SimType.Fun(SimType.Int, SimType.Unit)),
    SimType.Fun
      (SimType.Fun(SimType.Int, SimType.Unit),
      SimType.Fun(SimType.Int, SimType.Unit))) in
  let tyapply = SimType.Fun(SimType.Fun(SimType.Int, SimType.Unit), SimType.Fun(SimType.Int, SimType.Unit)) in
  let tycheck = SimType.Fun(SimType.Int, SimType.Fun(SimType.Int, SimType.Unit)) in
  let prog = { Prog.attr = [];
               Prog.fdefs = [main; applyh; apply; check1; check2];
               Prog.types = [Idnt.make "main", tymain; Idnt.make "applyh", tyapplyh; Idnt.make "apply", tyapply; Idnt.make "check", tycheck];
               Prog.main = main.Fdef.name } in
  Format.printf "%a" Prog.pr prog;
  infer [] prog


let test_apply_apply () =
  let main = { Fdef.attr = []; Fdef.name = Idnt.make "main"; Fdef.args = [Idnt.make "n"]; Fdef.guard = Term.make_true; Fdef.body = Term.apply (Term.make_var "apply") [Term.apply (Term.make_var "apply") [Term.apply (Term.make_var "check") [Term.make_var "n"]]; Term.make_var "n"] } in
  let apply = { Fdef.attr = []; Fdef.name = Idnt.make "apply"; Fdef.args = [Idnt.make "f"; Idnt.make "x"]; Fdef.guard = Term.make_true; Fdef.body = Term.apply (Term.make_var "f") [Term.make_var "x"] } in
  let check1 = { Fdef.attr = []; Fdef.name = Idnt.make "check"; Fdef.args = [Idnt.make "x1"; Idnt.make "x2"]; guard = Term.eq (Term.make_var "x1") (Term.make_var "x2"); Fdef.body = Term.make_unit} in
  let check2 = { Fdef.attr = []; Fdef.name = Idnt.make "check"; Fdef.args = [Idnt.make "x1"; Idnt.make "x2"]; guard = Term.neq (Term.make_var "x1") (Term.make_var "x2"); Fdef.body = Term.make_event "fail"} in
  let tymain = SimType.Fun(SimType.Int, SimType.Unit) in
  let tyapply = SimType.Fun(SimType.Fun(SimType.Int, SimType.Unit), SimType.Fun(SimType.Int, SimType.Unit)) in
  let tycheck = SimType.Fun(SimType.Int, SimType.Fun(SimType.Int, SimType.Unit)) in
  let prog = { Prog.attr = [];
               Prog.fdefs = [main; apply; check1; check2];
               Prog.types = [Idnt.make "main", tymain; Idnt.make "apply", tyapply; Idnt.make "check", tycheck];
               Prog.main = main.Fdef.name } in
  Format.printf "%a" Prog.pr prog;
  infer [] prog

let test_apply_apply2 () =
  let main = { Fdef.attr = []; Fdef.name = Idnt.make "main"; Fdef.args = [Idnt.make "n"]; Fdef.guard = Term.make_true; Fdef.body = Term.apply (Term.make_var "apply") [Term.apply (Term.make_var "apply2") [Term.make_var "check"; Term.make_var "n"]; Term.make_var "n"] } in
  let apply = { Fdef.attr = []; Fdef.name = Idnt.make "apply"; Fdef.args = [Idnt.make "f"; Idnt.make "x"]; Fdef.guard = Term.make_true; Fdef.body = Term.apply (Term.make_var "f") [Term.make_var "x"] } in
  let apply2 = { Fdef.attr = []; Fdef.name = Idnt.make "apply2"; Fdef.args = [Idnt.make "f"; Idnt.make "x"; Idnt.make "y"]; Fdef.guard = Term.make_true; Fdef.body = Term.apply (Term.make_var "f") [Term.make_var "x"; Term.make_var "y"] } in
  let check1 = { Fdef.attr = []; Fdef.name = Idnt.make "check"; Fdef.args = [Idnt.make "x1"; Idnt.make "x2"]; guard = Term.eq (Term.make_var "x1") (Term.make_var "x2"); Fdef.body = Term.make_unit} in
  let check2 = { Fdef.attr = []; Fdef.name = Idnt.make "check"; Fdef.args = [Idnt.make "x1"; Idnt.make "x2"]; guard = Term.neq (Term.make_var "x1") (Term.make_var "x2"); Fdef.body = Term.make_event "fail"} in
  let tymain = SimType.Fun(SimType.Int, SimType.Unit) in
  let tyapply = SimType.Fun(SimType.Fun(SimType.Int, SimType.Unit), SimType.Fun(SimType.Int, SimType.Unit)) in
  let tyapply2 = SimType.Fun(SimType.Fun(SimType.Int, SimType.Fun(SimType.Int, SimType.Unit)), SimType.Fun(SimType.Int, SimType.Fun(SimType.Int, SimType.Unit))) in
  let tycheck = SimType.Fun(SimType.Int, SimType.Fun(SimType.Int, SimType.Unit)) in
  let prog = { Prog.attr = [];
               Prog.fdefs = [main; apply; apply2; check1; check2];
               Prog.types = [Idnt.make "main", tymain; Idnt.make "apply", tyapply; Idnt.make "apply2", tyapply2; Idnt.make "check", tycheck];
               Prog.main = main.Fdef.name } in
  Format.printf "%a" Prog.pr prog;
  infer [[0; 0; 0; 1]] prog

let _ = test_sum ()
