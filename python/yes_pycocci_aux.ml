(*
 * Copyright 2005-2009, Ecole des Mines de Nantes, University of Copenhagen
 * Yoann Padioleau, Julia Lawall, Rene Rydhof Hansen, Henrik Stuart, Gilles Muller, Nicolas Palix
 * This file is part of Coccinelle.
 *
 * Coccinelle is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, according to version 2 of the License.
 *
 * Coccinelle is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Coccinelle.  If not, see <http://www.gnu.org/licenses/>.
 *
 * The authors reserve the right to distribute this or future versions of
 * Coccinelle under other licenses.
 *)


open Ast_c
open Common
open Pycaml

let call_pretty f a =
  let str = ref ([] : string list) in
  let pr_elem info = str := (Ast_c.str_of_info info) :: !str in
  let pr_sp _ = () in
  f ~pr_elem ~pr_space:pr_sp a;
  String.concat " " (List.rev !str)

let exprrep = call_pretty Pretty_print_c.pp_expression_gen

let stringrep mvb = match mvb with
  Ast_c.MetaIdVal        s -> s
| Ast_c.MetaFuncVal      s -> s
| Ast_c.MetaLocalFuncVal s -> s
| Ast_c.MetaExprVal      expr -> exprrep expr
| Ast_c.MetaExprListVal  expr_list -> "TODO: <<exprlist>>"
| Ast_c.MetaTypeVal      typ -> call_pretty Pretty_print_c.pp_type_gen typ
| Ast_c.MetaInitVal      ini -> call_pretty Pretty_print_c.pp_init_gen ini
| Ast_c.MetaStmtVal      statement ->
    call_pretty Pretty_print_c.pp_statement_gen statement
| Ast_c.MetaParamVal     param ->
    call_pretty Pretty_print_c.pp_param_gen param
| Ast_c.MetaParamListVal params -> "TODO: <<paramlist>>"
| Ast_c.MetaListlenVal n -> string_of_int n
| Ast_c.MetaPosVal (pos1, pos2) ->
    let print_pos = function
	Ast_cocci.Real x -> string_of_int x
      | Ast_cocci.Virt(x,off) -> Printf.sprintf "%d+%d" x off in
    Common.sprintf ("pos(%s,%s)") (print_pos pos1) (print_pos pos2)
| Ast_c.MetaPosValList positions -> "TODO: <<postvallist>>"

