open Syntax

(** Encode mutable record as record with references *)
val mutable_record : term -> term

(** Encode record as tuple *)
val record : term -> term

(** Encode simple variant as integer *)
val variant : term -> term

(** Encode list as function *)
val list : term -> term * ((Syntax.id -> Ref_type.t) -> Syntax.id -> Ref_type.t)

(** Encode recursive data as function *)
val recdata : term -> term

(** Encode recursive data as function with reference *)
val array : term -> term

(** Abstract away content of reference *)
val abst_ref : term -> term

val all : term -> term

val typ_of : (term -> term) -> typ -> typ
