(* on the first pass, onlyModif is true, so we don't see all matched nodes,
only modified ones *)

module Ast = Ast_cocci
module V = Visitor_ast
module CTL = Ast_ctl

let mcode r (_,_,kind) =
  match kind with
    Ast.MINUS(_,_) -> true
  | Ast.PLUS -> failwith "not possible"
  | Ast.CONTEXT(_,info) -> not (info = Ast.NOTHING)

let no_mcode _ _ = false

let contains_modif used_after x =
  if List.exists (function x -> List.mem x used_after) (Ast.get_fvs x)
  then true
  else
    let bind x y = x or y in
    let option_default = false in
    let do_nothing r k e = k e in
    let rule_elem r k re =
      let res = k re in
      match Ast.unwrap re with
	Ast.FunHeader(bef,_,fninfo,name,lp,params,rp) ->
	  bind (mcode r ((),(),bef)) res
      | Ast.Decl(bef,_,decl) ->
	  bind (mcode r ((),(),bef)) res
      | _ -> res in
    let recursor =
      V.combiner bind option_default
	mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode
	mcode mcode
	do_nothing do_nothing do_nothing do_nothing
	do_nothing do_nothing do_nothing do_nothing do_nothing do_nothing
	do_nothing rule_elem do_nothing do_nothing do_nothing do_nothing in
    recursor.V.combiner_rule_elem x

(* contains an inherited metavariable or contains a constant *)
let contains_constant x =
  match Ast.get_inherited x with
    [] ->
      let bind x y = x or y in
      let option_default = false in
      let do_nothing r k e = k e in
      let mcode _ _ = false in
      let ident r k i =
	match Ast.unwrap i with
	  Ast.Id(name) -> true
	| _ -> k i in
      let expr r k e =
	match Ast.unwrap e with
	  Ast.Constant(const) -> true
	| _ -> k e in
      let recursor =
	V.combiner bind option_default
	  mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode
	  mcode mcode
	  do_nothing do_nothing do_nothing do_nothing
	  ident expr do_nothing do_nothing do_nothing do_nothing
	  do_nothing do_nothing do_nothing do_nothing do_nothing do_nothing in
      recursor.V.combiner_rule_elem x
  | _ -> true

(* --------------------------------------------------------------------- *)

let print_info = function
    [] -> Printf.printf "no information\n"
  | l ->
      List.iter
	(function disj ->
	  Printf.printf "one set of required things %d:\n"
	    (List.length disj);
	  List.iter
	    (function thing ->
	      Printf.printf "%s\n"
		(Pretty_print_cocci.rule_elem_to_string thing))
	    disj;)
	l

(* --------------------------------------------------------------------- *)

(* drop all distinguishing information from a term *)
let strip =
  let do_nothing r k e = Ast.make_term (Ast.unwrap (k e)) in
  let do_absolutely_nothing r k e = k e in
  let mcode m = Ast.make_mcode(Ast.unwrap_mcode m) in
  let rule_elem r k re =
    let res = do_nothing r k re in
    let no_mcode = Ast.CONTEXT(Ast.NoPos,Ast.NOTHING) in
    match Ast.unwrap res with
      Ast.FunHeader(bef,b,fninfo,name,lp,params,rp) ->
	Ast.rewrap res
	  (Ast.FunHeader(no_mcode,b,fninfo,name,lp,params,rp))
    | Ast.Decl(bef,b,decl) -> Ast.rewrap res (Ast.Decl(no_mcode,b,decl))
    | _ -> res in
  let recursor =
    V.rebuilder
      mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode
      mcode
      do_nothing do_nothing do_nothing do_nothing
      do_nothing do_nothing do_nothing do_nothing do_nothing do_nothing
      do_nothing rule_elem do_nothing do_nothing
      do_nothing do_absolutely_nothing in
  recursor.V.rebuilder_rule_elem

(* --------------------------------------------------------------------- *)

let disj l1 l2 = Common.union_set l1 l2

let rec conj xs ys =
  match (xs,ys) with
    ([],_) -> ys
  | (_,[]) -> xs
  | _ ->
      List.fold_left
	(function prev ->
	  function x ->
	    List.fold_left
	      (function prev ->
		function cur ->
		  let cur_res = (List.sort compare (Common.union_set x cur)) in
		  cur_res ::
		  (List.filter
		     (function x -> not (Common.include_set cur_res x))
		     prev))
	      prev ys)
	[] xs

let conj_one testfn x l =
  if testfn x
  then conj [[strip x]] l
  else l

let conj_wrapped x l = conj [List.map strip x] l

(* --------------------------------------------------------------------- *)
(* the main translation loop *)

let rec statement_list testfn mcode tail stmt_list : 'a list list =
  match Ast.unwrap stmt_list with
    Ast.DOTS(x) | Ast.CIRCLES(x) | Ast.STARS(x) ->
      (match List.rev x with
	[] -> []
      |	last::rest ->
	  List.fold_right
	    (function cur ->
	      function rest ->
		conj (statement testfn mcode false cur) rest)
	    rest (statement testfn mcode tail last))

and statement testfn mcode tail stmt : 'a list list =
  match Ast.unwrap stmt with
    Ast.Atomic(ast) ->
      (match Ast.unwrap ast with
	(* modifications on return are managed in some other way *)
	Ast.Return(_,_) | Ast.ReturnExpr(_,_,_) when tail -> []
      |	_ -> if testfn ast then [[strip ast]] else [])
  | Ast.Seq(lbrace,decls,body,rbrace) ->
      let body_info =
	conj
	  (statement_list testfn mcode false decls)
	  (statement_list testfn mcode tail body) in
      if testfn lbrace or testfn rbrace
      then conj_wrapped [lbrace;rbrace] body_info
      else body_info

  | Ast.IfThen(header,branch,(_,_,_,aft))
  | Ast.While(header,branch,(_,_,_,aft))
  | Ast.For(header,branch,(_,_,_,aft)) ->
      if testfn header or mcode () ((),(),aft)
      then conj_wrapped [header] (statement testfn mcode tail branch)
      else statement testfn mcode tail branch

  | Ast.Switch(header,lb,cases,rb) ->
      let body_info = case_lines  testfn mcode tail cases in
      if testfn header or testfn lb or testfn rb
      then conj_wrapped [header] body_info
      else body_info

  | Ast.IfThenElse(ifheader,branch1,els,branch2,(_,_,_,aft)) ->
      let branches =
	conj
	  (statement testfn mcode tail branch1)
	  (statement testfn mcode tail branch2) in
      if testfn ifheader or mcode () ((),(),aft)
      then conj_wrapped [ifheader] branches
      else branches

  | Ast.Disj(stmt_dots_list) ->
      List.fold_left
	(function prev ->
	  function cur ->
	    disj (statement_list testfn mcode tail cur) prev)
	[] stmt_dots_list

  | Ast.Nest(stmt_dots,whencode,t) ->
      (match Ast.unwrap stmt_dots with
	Ast.DOTS([l]) ->
	  (match Ast.unwrap l with
	    Ast.MultiStm(stm) ->
	      statement testfn mcode tail stm
	  | _ -> [])
      | _ -> [])

  | Ast.Dots((_,i,d),whencodes,t) -> []

  | Ast.FunDecl(header,lbrace,decls,body,rbrace) ->
      let body_info =
	conj
	  (statement_list testfn mcode false decls)
	  (statement_list testfn mcode true body) in
      if testfn header or testfn lbrace or testfn rbrace
      then conj_wrapped [header] body_info
      else body_info

  | Ast.Define(header,body) ->
      conj_one testfn header (statement_list testfn mcode tail body)

  | Ast.OptStm(stm) ->
      statement testfn mcode tail stm

  | Ast.UniqueStm(stm) | Ast.MultiStm(stm) ->
      statement testfn mcode tail stm

  | _ -> failwith "not supported"

and case_lines testfn mcode tail cases =
  match cases with
    [] -> []
  | last::rest ->
      List.fold_right
	(function cur ->
	  function rest ->
	    conj (case_line testfn mcode false cur) rest)
	rest (case_line testfn mcode tail last)

and case_line testfn mcode tail case =
  match Ast.unwrap case with
    Ast.CaseLine(header,code) ->
      conj_one testfn header (statement_list testfn mcode tail code)
	  
  | Ast.OptCase(case) -> failwith "not supported"

(* --------------------------------------------------------------------- *)
(* Function declaration *)

let top_level testfn mcode t : 'a list list =
  match Ast.unwrap t with
    Ast.FILEINFO(old_file,new_file) -> failwith "not supported fileinfo"
  | Ast.DECL(stmt) -> statement testfn mcode false stmt
  | Ast.CODE(stmt_dots) -> statement_list testfn mcode false stmt_dots
  | Ast.ERRORWORDS(exps) -> failwith "not supported errorwords"

(* --------------------------------------------------------------------- *)
(* Entry points *)

let debug = false

(* if we end up with nothing, we assume that this rule is only here because
someone depends on it, and thus we try again with testfn as contains_modif.
Alternatively, we could check that this rule is mentioned in some
dependency, but that would be a little more work, and doesn't seem
worthwhile. *)
let asttomember (_,_,l) used_after =
  let process_one l =
    if debug
    then print_info l;
    List.map (List.map (function x -> (Lib_engine.Match(x),CTL.Control))) l in
  List.map2
    (function min -> function max ->
      match min with
	[] -> process_one max
      |	_ -> process_one min)
    (List.map (top_level contains_constant no_mcode) l)
    (List.map2
       (function x -> function ua -> top_level (contains_modif ua) mcode x)
       l used_after)
