(* Ocsigen
 * Copyright (C) 2005 Vincent Balat
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

include Ocsigen_lib_base

module String = String_base

(*****************************************************************************)

module Ip_address = struct
  exception No_such_host

  let get_inet_addr ?(v6=false) host =
    let rec aux = function
      | [] -> Lwt.fail No_such_host
      | {Unix.ai_addr=Unix.ADDR_INET (inet_addr, _)}::_ -> Lwt.return inet_addr
      | _::l -> aux l
    in
    let options = [if v6 then Lwt_unix.AI_FAMILY Lwt_unix.PF_INET6 else Lwt_unix.AI_FAMILY Lwt_unix.PF_INET] in
    Lwt.bind
      (Lwt_unix.getaddrinfo host "" options)
      aux

end

(*****************************************************************************)

module Filename = struct

  include Filename

  let basename f =
    let n = String.length f in
    let i = try String.rindex f '\\' + 1 with Not_found -> 0 in
    let j = try String.rindex f '/' + 1 with Not_found -> 0 in
    let k = max i j in
    if k < n then
      String.sub f k (n-k)
    else
      "none"

  let extension_no_directory filename =
    try
      let pos = String.rindex filename '.' in
      String.sub filename (pos+1) ((String.length filename) - pos - 1)
    with Not_found ->
      raise Not_found

  let extension filename =
    try
      let pos = String.rindex filename '.'
      and slash =
        try String.rindex filename '/'
        with Not_found -> -1
      in
      if pos > slash then
        String.sub filename (pos+1) ((String.length filename) - pos - 1)
      else (* Dot before a directory separator *)
        raise Not_found
    with Not_found -> (* No dot in filename *)
      raise Not_found

end

(*****************************************************************************)

let make_cryptographic_safe_string =
  let rng = Cryptokit.Random.device_rng "/dev/urandom" in
  fun () ->
    let random_part =
      let random_number = Cryptokit.Random.string rng 20 in
      let to_b64 = Cryptokit.Base64.encode_compact () in
      Cryptokit.transform_string to_b64 random_number
    and sequential_part =
      (*VVV Use base 64 also here *)
      Printf.sprintf "%Lx" (Int64.bits_of_float (Unix.gettimeofday ())) in
    random_part ^ sequential_part

(* The string is produced from the concatenation of two components:
   a 160-bit random sequence obtained from /dev/urandom, and a
   64-bit sequential component derived from the system clock.  The
   former is supposed to prevent session spoofing.  The assumption
   is that given the high cryptographic quality of /dev/urandom, it
   is impossible for an attacker to deduce the sequence of random
   numbers produced.  As for the latter component, it exists to
   prevent a theoretical (though infinitesimally unlikely) session
   ID collision if the server were to be restarted.
*)


module Url = struct

  include Url_base

  (* Taken from Neturl version 1.1.2 *)
  let problem_re1 = Netstring_pcre.regexp "[ <>\"{}|\\\\^\\[\\]`]"

  let fixup_url_string1 =
    Netstring_pcre.global_substitute
      problem_re1
      (fun m s ->
         Printf.sprintf "%%%02x"
           (Char.code s.[Netstring_pcre.match_beginning m]))

  (* I add this fixup to handle %uxxxx sent by browsers.
     Translated to %xx%xx *)
  let problem_re2 = Netstring_pcre.regexp "\\%u(..)(..)"

  let fixup_url_string s =
    fixup_url_string1
      (Netstring_pcre.global_substitute
         problem_re2
         (fun m s ->
            String.concat "" ["%"; Netstring_pcre.matched_group m 1 s;
                              "%"; Netstring_pcre.matched_group m 2 s]
         )
         s)

  (*VVV This is in Netencoding but we have a problem with ~
        (not encoded by browsers). Here is a patch that does not encode '~': *)
  module MyUrl = struct

    let percent_encode =
      let lengths =
        let l = Array.make 256 3 in
        String.iter (fun c -> l.(Char.code c) <- 1)
          (* Unreserved Characters (section 2.3 of RFC 3986) *)
          "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~";
        l
      in
      fun s ->
        let l = String.length s in
        let l' = ref 0 in
        for i = 0 to l - 1 do
          l' := !l' + lengths.(Char.code s.[i])
        done;
        if l = !l' then
          String.copy s
        else
          let s' = Bytes.create !l' in
          let j = ref 0 in
          let hex = "0123456789ABCDEF" in
          for i = 0 to l - 1 do
            let c = s.[i] in
            let n = Char.code s.[i] in
            let d = lengths.(n) in
            if d = 1 then
              Bytes.set s' !j c
            else begin
              Bytes.set s' !j '%';
              Bytes.set s' (!j + 1) hex.[n lsr 4];
              Bytes.set s' (!j + 2) hex.[n land 0xf]
            end;
            j := !j + d
          done;
          Bytes.unsafe_to_string s'

    let encode_plus =
      let lengths =
        let l = Array.make 256 3 in
        String.iter (fun c -> l.(Char.code c) <- 1)
          (* Unchanged characters + space (HTML spec) *)
          "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.* ";
        l
      in
      fun s ->
        let l = String.length s in
        let l' = ref 0 in
        for i = 0 to l - 1 do
          l' := !l' + lengths.(Char.code s.[i])
        done;
        let s' = Bytes.create !l' in
        let j = ref 0 in
        let hex = "0123456789ABCDEF" in
        for i = 0 to l - 1 do
          let c = s.[i] in
          let n = Char.code s.[i] in
          let d = lengths.(n) in
          if d = 1 then
            Bytes.set s' !j (if c =  ' ' then '+' else c)
          else begin
            Bytes.set s' !j '%';
            Bytes.set s' (!j + 1) hex.[n lsr 4];
            Bytes.set s' (!j + 2) hex.[n land 0xf]
          end;
          j := !j + d
        done;
        Bytes.unsafe_to_string s'

    let encode ?(plus = true) s =
      if plus then encode_plus s else percent_encode s

  end

  let encode = MyUrl.encode
  let decode ?plus a = Netencoding.Url.decode ?plus a

  let make_encoded_parameters params =
    String.concat "&"
      (List.map (fun (name, value) -> encode name ^ "=" ^ encode value) params)

  let string_of_url_path ~encode l =
    if encode
    then
      fixup_url_string (String.concat "/"
                          (List.map (*Netencoding.Url.encode*)
                             (MyUrl.encode ~plus:false) l))
      (* ' ' are not encoded to '+' in paths *)
    else String.concat "/" l (* BYXXX : check illicit characters *)


  let parse =

    (* We do not accept http://login:pwd@host:port (should we?). *)
    let url_re = Netstring_pcre.regexp "^([Hh][Tt][Tt][Pp][Ss]?)://([0-9a-zA-Z.-]+|\\[[0-9A-Fa-f:.]+\\])(:([0-9]+))?/([^\\?]*)(\\?(.*))?$" in
    let short_url_re = Netstring_pcre.regexp "^/([^\\?]*)(\\?(.*))?$" in
    (*  let url_relax_re = Netstring_pcre.regexp "^[Hh][Tt][Tt][Pp][Ss]?://[^/]+" in
    *)
    fun url ->

      let match_re = Netstring_pcre.string_match url_re url 0 in

      let (https, host, port, pathstring, query) =
        match match_re with
        | None ->
          (match Netstring_pcre.string_match short_url_re url 0 with
           | None -> raise Ocsigen_Bad_Request
           | Some m ->
             let path =
               fixup_url_string (Netstring_pcre.matched_group m 1 url)
             in
             let query =
               try
                 Some (fixup_url_string (Netstring_pcre.matched_group m 3 url))
               with Not_found -> None
             in
             (None, None, None, path, query))
        | Some m ->
          let path = fixup_url_string (Netstring_pcre.matched_group m 5 url) in
          let query =
            try Some (fixup_url_string (Netstring_pcre.matched_group m 7 url))
            with Not_found -> None
          in
          let https =
            try (match Netstring_pcre.matched_group m 1 url with
                | "http" -> Some false
                | "https" -> Some true
                | _ -> None)
            with Not_found -> None in
          let host =
            try Some (Netstring_pcre.matched_group m 2 url)
            with Not_found -> None in
          let port =
            try Some (int_of_string (Netstring_pcre.matched_group m 4 url))
            with Not_found -> None in
          (https, host, port, path, query)
      in

      (* Note that the fragment (string after #) is not sent by browsers *)

      (*20110707 ' ' is encoded to '+' in queries, but not in paths.
        Warning: if we write the URL manually, we must encode ' ' to '+' manually
        (not done by the browser).
        --Vincent
      *)

      let get_params =
        lazy begin
          let params_string = match query with None -> "" | Some s -> s in
          try
            Netencoding.Url.dest_url_encoded_parameters params_string
          with Failure _ -> raise Ocsigen_Bad_Request
        end
      in

      let path = List.map (Netencoding.Url.decode ~plus:false) (Neturl.split_path pathstring) in
      let path = remove_dotdot path (* and remove "//" *)
      (* here we remove .. from paths, as it is dangerous.
         But in some very particular cases, we may want them?
         I prefer forbid that. *)
      in
      let uri_string = match query with
        | None -> pathstring
        | Some s -> String.concat "?" [pathstring; s]
      in

      (https, host, port, uri_string, path, query, get_params)

  let split_path = Neturl.split_path

  let prefix_and_path_of_t url =
    let (https, host, port, _, path, _, _) = parse url in
    let https_str = match https with
    | None -> ""
    | Some x -> if x then "https://" else "http://"
    in
    let host_str = match host with
    | None -> ""
    | Some x -> x
    in
    let port_str = match port with
    | None -> ""
    | Some x -> string_of_int x
    in
    (https_str ^ host_str ^ ":" ^ port_str, path)

end
