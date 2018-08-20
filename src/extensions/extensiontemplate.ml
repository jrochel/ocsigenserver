(* Ocsigen
 * http://www.ocsigen.org
 * Module extensiontemplate.ml
 * Copyright (C) 2007 Vincent Balat
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, with linking exception;
 * either version 2.1 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
*)
(*****************************************************************************)
(*****************************************************************************)
(* This is an example of extension for Ocsigen                               *)
(* Take this as a template for writing your own extensions to the Web server *)
(*****************************************************************************)
(*****************************************************************************)

(* If you want to create an extension to filter the output of the server
   (for ex: compression), have a look at deflatemod.ml as an example.
   It is very similar to this example, but using
   Ocsigen_extensions.register_output_filter
   instead of Ocsigen_extensions.register_extension.
*)

(* To compile it:
   ocamlfind ocamlc  -thread -package netstring-pcre,ocsigen -c extensiontemplate.ml

   Then load it dynamically from Ocsigen's config file:
   <extension module=".../extensiontemplate.cmo"/>

*)

open Lwt
open Ocsigen_extensions

(*****************************************************************************)
(** Extensions may take some options from the config file.
    These options are written in xml inside the <extension> tag.
    For example:
    <extension module=".../extensiontemplate.cmo">
     <myoption myattr="hello">
        ...
     </myoption>
    </extension>
*)

let rec parse_global_config = function
  | [] -> ()
  | (Xml.Element ("myoption", [("myattr", s)], []))::ll -> ()
  | _ -> raise (Error_in_config_file
                  ("Unexpected content inside extensiontemplate config"))



(*****************************************************************************)
(** The function that will generate the pages from the request, or modify
    a result generated by another extension.

    - a value of type [Ocsigen_extensions.conf_info] containing
    the current configuration options
    - [Ocsigen_extensions.req_state] is the request, possibly modified by previous
    extensions, or already found

*)
let gen = function
  | Ocsigen_extensions.Req_found _ ->
    (* If previous extension already found the page, you can
       modify the result (if you write a filter) or return it
       without modification like this: *)
    Lwt.return Ocsigen_extensions.Ext_do_nothing
  | Ocsigen_extensions.Req_not_found (err, ri) ->
    (* If previous extensions did not find the result,
       I decide here to answer with a default page
       (for the example):
    *)
    return (Ext_found
              (fun () ->
                 let content = "Extensiontemplate page" in
                 Ocsigen_senders.Text_content.result_of_content
                   (content, "text/plain")))



(*****************************************************************************)
(** Extensions may define new tags for configuring each site.
    These tags are inside <site ...>...</site> in the config file.

    For example:
    <site dir="">
     <extensiontemplate module=".../mymodule.cmo" />
    </site>

    Each extension will set its own configuration options, for example:
    <site dir="">
     <extensiontemplate module=".../mymodule.cmo" />
     <eliom module=".../myeliommodule.cmo" />
     <static dir="/var/www/plop" />
    </extension>

    Here parse_site is the function used to parse the config file inside this
    site. Use this if you want to put extensions config options inside
    your own option. For example:

    {[
      | Element ("iffound", [], sub) ->
        let ext = parse_fun sub in
        (* DANGER: parse_fun MUST be called BEFORE the function! *)
        (fun charset -> function
           | Ocsigen_extensions.Req_found (_, _) ->
             Lwt.return (Ext_sub_result ext)
           | Ocsigen_extensions.Req_not_found (err, ri) ->
             Lwt.return (Ocsigen_extensions.Ext_not_found err))
    ]}
*)

let parse_config path _ parse_site = function
  | Xml.Element ("extensiontemplate", atts, []) -> gen
  | Xml.Element (t, _, _) -> raise (Bad_config_tag_for_extension t)
  | _ ->
    raise (Error_in_config_file "Unexpected data in config file")




(*****************************************************************************)
(** Function to be called at the beginning of the initialisation phase
    of the server (actually each time the config file is reloaded) *)
let begin_init () =
  ()

(** Function to be called at the end of the initialisation phase *)
let end_init () =
  ()



(*****************************************************************************)
(** A function that will create an error message from the exceptions
    that may be raised during the initialisation phase, and raise again
    all other exceptions. That function has type exn -> string. Use the
    raise function if you don't need any. *)
let exn_handler = raise




(*****************************************************************************)
(* a function taking
   {ul
     {- the name of the virtual <host>}}
     that will be called for each <host>,
     and that will generate a function taking:
   {ul
     {- the path attribute of a <site> tag
     that will be called for each <site>,
     and that will generate a function taking:}}
   {ul
     {- an item of the config file
     that will be called on each tag inside <site> and:}
   {ul
     {- raise [Bad_config_tag_for_extension] if it does not recognize that tag}
     {- return something of type [extension] (filter or page generator)}}
*)
let site_creator
    (hostpattern : Ocsigen_extensions.virtual_hosts)
    (config_info : Ocsigen_extensions.config_info)
  = parse_config
(* hostpattern has type Ocsigen_extensions.virtual_hosts
   and represents the name of the virtual host.
   The path and the charset are declared in <site path... charset=.../>
*)


(* Same thing if the extension is loaded inside a local config
   file (using the userconf extension). However, we receive
   one additional argument, the root of the files the user
   can locally serve. See staticmod and userconf for details *)
let user_site_creator (path : Ocsigen_extensions.userconf_info) = site_creator

(*****************************************************************************)
(** Registration of the extension *)
let () = register_extension
    ~name:"extensionname"
    ~fun_site:site_creator

    (* If your extension is safe for users and if you want to allow
       exactly the same options as for global configuration, use the same
       [site_creator] function for [user_fun_site] as for [fun_site].

       If you don't want to allow users to use that extension in their
       configuration files, you can omit user_fun_site.
    *)
    ~user_fun_site:user_site_creator
    ~init_fun: parse_global_config

    ~begin_init ~end_init ~exn_handler
    ()
