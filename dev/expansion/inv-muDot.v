
(*
slightly outdated comment:

In trm_new and in object, we only allow Ds, not any type, because that's the
simplest thing which has a stable expansion under narrowing.
Thus, expansion is only needed as a "helper" for has.
We allow subsumption in all judgments, including expansion and has.
Since has is imprecise, it's not unique, so we can't do the transitivity 
push-back, but we hope that we won't need it. However, we need transitivity
in many places, so we add it as a rule. This also allows us to simplify the
subtyp_sel_l/r rules: There's no need to "bake in" transitivity.

Moreover, since invert_subtyp_bind seems difficult to prove, we just add it
as a subdecs rule. This also requires additional subdec and subtyp rules.
The rules work and weakening and substitution seems to work as well, but
it doesn't help a lot, because decs_has_preserves_sub, which was trivial
before, doesn't hold any more: If we're in a contradictory environment,
and the subdecs judgment was obtained from a subtyp_bind using the inversion
rule, there's no way we can "invent" a D1.
Preservation doesn't need decs_has_preserves_sub and becomes simpler, but
progress needs something like decs_has_preserves_sub, in order to assert
that if we get a subsumed member in the imprecise typing judgment, there
exists a (precise) member in the store. And doing this requires a real
invert_subtyp_bind.
So it seems that the inversion rules just avoid the problem, but it still
has to be solved. And they don't push it to another place where it's easier
to solve, so they're useless.
*)

Set Implicit Arguments.

(* CoqIDE users: Run open.sh (in ./ln) to start coqide, then open this file. *)
Require Import LibLN.


(* ###################################################################### *)
(* ###################################################################### *)
(** * Definitions *)

(* ###################################################################### *)
(** ** Syntax *)

(** If it's clear whether a type, field or method is meant, we use nat, 
    if not, we use label: *)
Inductive label: Type :=
| label_typ: nat -> label
| label_fld: nat -> label
| label_mtd: nat -> label.

Inductive avar : Type :=
  | avar_b : nat -> avar  (* bound var (de Bruijn index) *)
  | avar_f : var -> avar. (* free var ("name"), refers to tenv or venv *)

Inductive pth : Type :=
  | pth_var : avar -> pth.

Inductive typ : Type :=
  | typ_top  : typ
  | typ_bot  : typ
  | typ_bind : decs -> typ (* { z => decs } *)
  | typ_sel : pth -> label -> typ (* p.L *)
with dec : Type :=
  | dec_typ  : typ -> typ -> dec
  | dec_fld  : typ -> dec
  | dec_mtd : typ -> typ -> dec
with decs : Type :=
  | decs_nil : decs
  | decs_cons : nat -> dec -> decs -> decs.

Inductive trm : Type :=
  | trm_var  : avar -> trm
  | trm_new  : decs -> defs -> trm
  | trm_sel  : trm -> nat -> trm
  | trm_call : trm -> nat -> trm -> trm
with def : Type :=
  | def_typ : def (* just a placeholder *)
  | def_fld : avar -> def (* cannot have term here, need to assign first *)
  | def_mtd : trm -> def (* one nameless argument *)
with defs : Type :=
  | defs_nil : defs
  | defs_cons : nat -> def -> defs -> defs.

Inductive obj : Type :=
  | object : decs -> defs -> obj. (* { z => Ds }{ z => ds } *)

(** *** Typing environment ("Gamma") *)
Definition ctx := env typ.

(** *** Value environment ("store") *)
Definition sto := env obj.

(** *** Syntactic sugar *)
Definition trm_fun(T U: typ)(body: trm) := 
            trm_new (decs_cons 0 (dec_mtd T U)  decs_nil)
                    (defs_cons 0 (def_mtd body) defs_nil).
Definition trm_app(func arg: trm) := trm_call func 0 arg.
Definition trm_let(T U: typ)(rhs body: trm) := trm_app (trm_fun T U body) rhs.
Definition typ_arrow(T1 T2: typ) := typ_bind (decs_cons 0 (dec_mtd T1 T2) decs_nil).


(* ###################################################################### *)
(** ** Declaration and definition lists *)

Definition label_for_def(n: nat)(d: def): label := match d with
| def_typ     => label_typ n
| def_fld _   => label_fld n
| def_mtd _   => label_mtd n
end.
Definition label_for_dec(n: nat)(D: dec): label := match D with
| dec_typ _ _ => label_typ n
| dec_fld _   => label_fld n
| dec_mtd _ _ => label_mtd n
end.

Fixpoint get_def(l: label)(ds: defs): option def := match ds with
| defs_nil => None
| defs_cons n d ds' => If l = label_for_def n d then Some d else get_def l ds'
end.
Fixpoint get_dec(l: label)(Ds: decs): option dec := match Ds with
| decs_nil => None
| decs_cons n D Ds' => If l = label_for_dec n D then Some D else get_dec l Ds'
end.

Definition defs_has(ds: defs)(l: label)(d: def): Prop := (get_def l ds = Some d).
Definition decs_has(Ds: decs)(l: label)(D: dec): Prop := (get_dec l Ds = Some D).

Definition defs_hasnt(ds: defs)(l: label): Prop := (get_def l ds = None).
Definition decs_hasnt(Ds: decs)(l: label): Prop := (get_dec l Ds = None).


(* ###################################################################### *)
(** ** Opening *)

(** Opening replaces in some syntax a bound variable with dangling index (k) 
   by a free variable x. *)

Definition open_rec_avar (k: nat) (u: var) (a: avar) : avar :=
  match a with
  | avar_b i => If k = i then avar_f u else avar_b i
  | avar_f x => avar_f x
  end.

Definition open_rec_pth (k: nat) (u: var) (p: pth) : pth :=
  match p with
  | pth_var a => pth_var (open_rec_avar k u a)
  end.

Fixpoint open_rec_typ (k: nat) (u: var) (T: typ) { struct T } : typ :=
  match T with
  | typ_top     => typ_top
  | typ_bot     => typ_bot
  | typ_bind Ds => typ_bind (open_rec_decs (S k) u Ds)
  | typ_sel p L => typ_sel (open_rec_pth k u p) L
  end
with open_rec_dec (k: nat) (u: var) (D: dec) { struct D } : dec :=
  match D with
  | dec_typ T U => dec_typ (open_rec_typ k u T) (open_rec_typ k u U)
  | dec_fld T   => dec_fld (open_rec_typ k u T)
  | dec_mtd T U => dec_mtd (open_rec_typ k u T) (open_rec_typ k u U)
  end
with open_rec_decs (k: nat) (u: var) (Ds: decs) { struct Ds } : decs :=
  match Ds with
  | decs_nil          => decs_nil
  | decs_cons n D Ds' => decs_cons n (open_rec_dec k u D) (open_rec_decs k u Ds')
  end.

Fixpoint open_rec_trm (k: nat) (u: var) (t: trm) { struct t } : trm :=
  match t with
  | trm_var a      => trm_var (open_rec_avar k u a)
  | trm_new Ds ds  => trm_new (open_rec_decs k u Ds) (open_rec_defs (S k) u ds)
  | trm_sel e n    => trm_sel (open_rec_trm k u e) n
  | trm_call o m a => trm_call (open_rec_trm k u o) m (open_rec_trm k u a)
  end
with open_rec_def (k: nat) (u: var) (d: def) { struct d } : def :=
  match d with
  | def_typ   => def_typ
  | def_fld a => def_fld (open_rec_avar k u a)
  | def_mtd e => def_mtd (open_rec_trm (S k) u e)
  end
with open_rec_defs (k: nat) (u: var) (ds: defs) { struct ds } : defs :=
  match ds with
  | defs_nil => defs_nil
  | defs_cons n d tl => defs_cons n (open_rec_def k u d) (open_rec_defs k u tl)
  end.

Definition open_avar u a := open_rec_avar  0 u a.
Definition open_pth  u p := open_rec_pth   0 u p.
Definition open_typ  u t := open_rec_typ   0 u t.
Definition open_dec  u d := open_rec_dec   0 u d.
Definition open_decs u l := open_rec_decs  0 u l.
Definition open_trm  u e := open_rec_trm   0 u e.
Definition open_def  u d := open_rec_def   0 u d.
Definition open_defs u l := open_rec_defs  0 u l.


(* ###################################################################### *)
(** ** Free variables *)

Definition fv_avar (a: avar) : vars :=
  match a with
  | avar_b i => \{}
  | avar_f x => \{x}
  end.

Definition fv_pth (p: pth) : vars :=
  match p with
  | pth_var a => fv_avar a
  end.

Fixpoint fv_typ (T: typ) { struct T } : vars :=
  match T with
  | typ_top     => \{}
  | typ_bot     => \{}
  | typ_bind Ds => fv_decs Ds
  | typ_sel p L => fv_pth p
  end
with fv_dec (D: dec) { struct D } : vars :=
  match D with
  | dec_typ T U => (fv_typ T) \u (fv_typ U)
  | dec_fld T   => (fv_typ T)
  | dec_mtd T U => (fv_typ T) \u (fv_typ U)
  end
with fv_decs (Ds: decs) { struct Ds } : vars :=
  match Ds with
  | decs_nil          => \{}
  | decs_cons n D Ds' => (fv_dec D) \u (fv_decs Ds')
  end.

(* Since we define defs ourselves instead of using [list def], we don't have any
   termination proof problems: *)
Fixpoint fv_trm (t: trm) : vars :=
  match t with
  | trm_var x        => (fv_avar x)
  | trm_new Ds ds    => (fv_decs Ds) \u (fv_defs ds)
  | trm_sel t l      => (fv_trm t)
  | trm_call t1 m t2 => (fv_trm t1) \u (fv_trm t2)
  end
with fv_def (d: def) : vars :=
  match d with
  | def_typ   => \{}
  | def_fld x => fv_avar x
  | def_mtd u => fv_trm u
  end
with fv_defs(ds: defs) : vars :=
  match ds with
  | defs_nil         => \{}
  | defs_cons n d tl => (fv_def d) \u (fv_defs tl)
  end.


(* ###################################################################### *)
(** ** Operational Semantics *)

(** Note: Terms given by user are closed, so they only contain avar_b, no avar_f.
    Whenever we introduce a new avar_f (only happens in red_new), we choose one
    which is not in the store, so we never have name clashes. *)
Inductive red : trm -> sto -> trm -> sto -> Prop :=
  (* computation rules *)
  | red_call : forall s x y m T ds body,
      binds x (object T ds) s ->
      defs_has (open_defs x ds) (label_mtd m) (def_mtd body) ->
      red (trm_call (trm_var (avar_f x)) m (trm_var (avar_f y))) s
          (open_trm y body) s
  | red_sel : forall s x y l T ds,
      binds x (object T ds) s ->
      defs_has (open_defs x ds) (label_fld l) (def_fld y) ->
      red (trm_sel (trm_var (avar_f x)) l) s
          (trm_var y) s
  | red_new : forall s T ds x,
      x # s ->
      red (trm_new T ds) s
          (trm_var (avar_f x)) (s & x ~ (object T ds))
  (* congruence rules *)
  | red_call1 : forall s o m a s' o',
      red o s o' s' ->
      red (trm_call o  m a) s
          (trm_call o' m a) s'
  | red_call2 : forall s x m a s' a',
      red a s a' s' ->
      red (trm_call (trm_var (avar_f x)) m a ) s
          (trm_call (trm_var (avar_f x)) m a') s'
  | red_sel1 : forall s o l s' o',
      red o s o' s' ->
      red (trm_sel o  l) s
          (trm_sel o' l) s'.


(* ###################################################################### *)
(** ** Typing *)

(* all judgments are imprecise (can contain subsumption) *)

(* expansion returns a set of decs without opening them *)
Inductive exp : ctx -> typ -> decs -> Prop :=
  | exp_top : forall G, 
      exp G typ_top decs_nil
(*| exp_bot : typ_bot has no expansion *)
  | exp_bind : forall G Ds,
      exp G (typ_bind Ds) Ds
  | exp_sel : forall G x L Lo Hi Ds,
      has G (trm_var (avar_f x)) L (dec_typ Lo Hi) ->
      exp G Hi Ds ->
      exp G (typ_sel (pth_var (avar_f x)) L) Ds
with has : ctx -> trm -> label -> dec -> Prop :=
  | has_trm : forall G t T Ds l D,
      ty_trm G t T ->
      exp G T Ds ->
      decs_has Ds l D ->
      (forall z, (open_dec z D) = D) ->
      has G t l D
  | has_var : forall G v T Ds l D,
      ty_trm G (trm_var (avar_f v)) T ->
      exp G T Ds ->
      decs_has Ds l D ->
      has G (trm_var (avar_f v)) l (open_dec v D)
with subtyp : ctx -> typ -> typ -> Prop :=
  | subtyp_refl : forall G x L,
      subtyp G (typ_sel (pth_var (avar_f x)) L) (typ_sel (pth_var (avar_f x)) L)
  | subtyp_top : forall G T,
      subtyp G T typ_top
  | subtyp_bot : forall G T,
      subtyp G typ_bot T
  | subtyp_bind : forall L G Ds1 Ds2,
      (forall z, z \notin L -> 
         subdecs (G & z ~ (typ_bind Ds1))
                 (open_decs z Ds1) 
                 (open_decs z Ds2)) ->
      subtyp G (typ_bind Ds1) (typ_bind Ds2)
  | subtyp_sel_l : forall G x L S U,
      has G (trm_var (avar_f x)) L (dec_typ S U) ->
      subtyp G (typ_sel (pth_var (avar_f x)) L) U
  | subtyp_sel_r : forall G x L S U,
      has G (trm_var (avar_f x)) L (dec_typ S U) ->
      subtyp G S (typ_sel (pth_var (avar_f x)) L)
  | subtyp_trans : forall G T1 T2 T3,
      subtyp G T1 T2 ->
      subtyp G T2 T3 ->
      subtyp G T1 T3
  | subtyp_inv_typ_lo : forall G T1 T2 Ds1 Ds2 l Lo1 Hi1 Lo2 Hi2,
      subtyp G T1 T2 ->
      exp G T1 Ds1 -> (* <-- TODO this one needs to be precise! *)
      exp G T2 Ds2 ->
      decs_has Ds1 l (dec_typ Lo1 Hi1) ->
      decs_has Ds2 l (dec_typ Lo2 Hi2) ->
      subtyp G Lo2 Lo1
  | subtyp_inv_typ_hi : forall G T1 T2 Ds1 Ds2 l Lo1 Hi1 Lo2 Hi2,
      subtyp G T1 T2 ->
      exp G T1 Ds1 ->
      exp G T2 Ds2 ->
      decs_has Ds1 l (dec_typ Lo1 Hi1) ->
      decs_has Ds2 l (dec_typ Lo2 Hi2) ->
      subtyp G Hi1 Hi2
  | subtyp_inv_fld : forall G T1 T2 Ds1 Ds2 l U1 U2,
      subtyp G T1 T2 ->
      exp G T1 Ds1 ->
      exp G T2 Ds2 ->
      decs_has Ds1 l (dec_fld U1) ->
      decs_has Ds2 l (dec_fld U2) ->
      subtyp G U1 U2
  | subtyp_inv_mtd_arg : forall G T1 T2 Ds1 Ds2 l A1 R1 A2 R2,
      subtyp G T1 T2 ->
      exp G T1 Ds1 ->
      exp G T2 Ds2 ->
      decs_has Ds1 l (dec_mtd A1 R1) ->
      decs_has Ds2 l (dec_mtd A2 R2) ->
      subtyp G A2 A1
  | subtyp_inv_mtd_ret : forall G T1 T2 Ds1 Ds2 l A1 R1 A2 R2,
      subtyp G T1 T2 ->
      exp G T1 Ds1 ->
      exp G T2 Ds2 ->
      decs_has Ds1 l (dec_mtd A1 R1) ->
      decs_has Ds2 l (dec_mtd A2 R2) ->
      subtyp G R1 R2
with subdec : ctx -> dec -> dec -> Prop :=
  | subdec_typ : forall G Lo1 Hi1 Lo2 Hi2,
      (* only allow implementable decl *)
      subtyp G Lo1 Hi1 ->
      subtyp G Lo2 Hi2 ->
      (* lhs narrower range than rhs *)
      subtyp G Lo2 Lo1 ->
      subtyp G Hi1 Hi2 ->
      (* conclusion *)
      subdec G (dec_typ Lo1 Hi1) (dec_typ Lo2 Hi2)
  | subdec_fld : forall G T1 T2,
      subtyp G T1 T2 ->
      subdec G (dec_fld T1) (dec_fld T2)
  | subdec_mtd : forall G S1 T1 S2 T2,
      subtyp G S2 S1 ->
      subtyp G T1 T2 ->
      subdec G (dec_mtd S1 T1) (dec_mtd S2 T2)
with subdecs : ctx -> decs -> decs -> Prop :=
  | subdecs_empty : forall G Ds,
      subdecs G Ds decs_nil
  | subdecs_push : forall G n Ds1 Ds2 D1 D2,
      decs_has   Ds1 (label_for_dec n D2) D1 ->
      subdec  G D1 D2 ->
      subdecs G Ds1 Ds2 ->
      subdecs G Ds1 (decs_cons n D2 Ds2)
with ty_trm : ctx -> trm -> typ -> Prop :=
  | ty_var : forall G x T,
      binds x T G ->
      ty_trm G (trm_var (avar_f x)) T
  | ty_sel : forall G t l T,
      has G t (label_fld l) (dec_fld T) ->
      ty_trm G (trm_sel t l) T
  | ty_call : forall G t m U V u,
      has G t (label_mtd m) (dec_mtd U V) ->
      ty_trm G u U ->
      ty_trm G (trm_call t m u) V
  | ty_new : forall L G ds Ds,
      (forall x, x \notin L ->
                 ty_defs (G & x ~ typ_bind Ds) (open_defs x ds) (open_decs x Ds)) ->
      (forall x, x \notin L ->
                 forall M S U, decs_has (open_decs x Ds) M (dec_typ S U) -> 
                               subtyp (G & x ~ typ_bind Ds) S U) ->
      ty_trm G (trm_new Ds ds) (typ_bind Ds)
  | ty_sbsm : forall G t T U,
      ty_trm G t T ->
      subtyp G T U ->
      ty_trm G t U
with ty_def : ctx -> def -> dec -> Prop :=
  | ty_typ : forall G S T,
      ty_def G def_typ (dec_typ S T)
  | ty_fld : forall G v T,
      ty_trm G (trm_var v) T ->
      ty_def G (def_fld v) (dec_fld T)
  | ty_mtd : forall L G S T t,
      (forall x, x \notin L -> ty_trm (G & x ~ S) (open_trm x t) T) ->
      ty_def G (def_mtd t) (dec_mtd S T)
with ty_defs : ctx -> defs -> decs -> Prop :=
  | ty_dsnil : forall G,
      ty_defs G defs_nil decs_nil
  | ty_dscons : forall G ds d Ds D n,
      ty_defs G ds Ds ->
      ty_def  G d D ->
      ty_defs G (defs_cons n d ds) (decs_cons n D Ds).


(** *** Well-formed store *)
Inductive wf_sto: sto -> ctx -> Prop :=
  | wf_sto_empty : wf_sto empty empty
  | wf_sto_push : forall s G x ds Ds,
      wf_sto s G ->
      x # s ->
      x # G ->
      (* What's below is the same as the ty_new rule, but we don't use ty_trm,
         because it could be subsumption *)
      ty_defs (G & x ~ typ_bind Ds) (open_defs x ds) (open_decs x Ds) ->
      (forall L S U, decs_has (open_decs x Ds) L (dec_typ S U) -> 
                     subtyp (G & x ~ typ_bind Ds) S U) ->
      wf_sto (s & x ~ (object Ds ds)) (G & x ~ typ_bind Ds).

(*
ty_trm_new does not check for good bounds recursively inside the types, but that's
not a problem because when creating an object x which has (L: S..U), we have two cases:
Case 1: The object x has a field x.f = y of type x.L: Then y has a type
        Y <: x.L, and when checking the creation of y, we checked that
        the type members of Y are good, so the those of S and U are good as well,
        because S and U are supertypes of Y.
Case 2: The object x has no field of type x.L: Then we can only refer to the
        type x.L, but not to possibly bad type members of the type x.L.
*)


(* ###################################################################### *)
(** ** Statements we want to prove *)

Definition progress := forall s G e T,
  wf_sto s G ->
  ty_trm G e T -> 
  (
    (* can step *)
    (exists e' s', red e s e' s') \/
    (* or is a value *)
    (exists x o, e = (trm_var (avar_f x)) /\ binds x o s)
  ).

Definition preservation := forall s G e T e' s',
  wf_sto s G -> ty_trm G e T -> red e s e' s' ->
  (exists G', wf_sto s' G' /\ ty_trm G' e' T).


(* ###################################################################### *)
(* ###################################################################### *)
(** * Infrastructure *)

(* ###################################################################### *)
(** ** Induction principles *)

Scheme trm_mut  := Induction for trm  Sort Prop
with   def_mut  := Induction for def  Sort Prop
with   defs_mut := Induction for defs Sort Prop.
Combined Scheme trm_mutind from trm_mut, def_mut, defs_mut.

Scheme typ_mut  := Induction for typ  Sort Prop
with   dec_mut  := Induction for dec  Sort Prop
with   decs_mut := Induction for decs Sort Prop.
Combined Scheme typ_mutind from typ_mut, dec_mut, decs_mut.

Scheme exp_mut     := Induction for exp     Sort Prop
with   has_mut     := Induction for has     Sort Prop
with   subtyp_mut  := Induction for subtyp  Sort Prop
with   subdec_mut  := Induction for subdec  Sort Prop
with   subdecs_mut := Induction for subdecs Sort Prop
with   ty_trm_mut  := Induction for ty_trm  Sort Prop
with   ty_def_mut  := Induction for ty_def  Sort Prop
with   ty_defs_mut := Induction for ty_defs Sort Prop.
Combined Scheme ty_mutind from exp_mut, has_mut,
                               subtyp_mut, subdec_mut, subdecs_mut,
                               ty_trm_mut, ty_def_mut, ty_defs_mut.

Scheme has_mut2    := Induction for has    Sort Prop
with   ty_trm_mut2 := Induction for ty_trm Sort Prop.
Combined Scheme ty_has_mutind from has_mut2, ty_trm_mut2.

(* ###################################################################### *)
(** ** Tactics *)

Ltac auto_specialize :=
  repeat match goal with
  | Impl: ?Cond ->            _ |- _ => let HC := fresh in 
      assert (HC: Cond) by auto; specialize (Impl HC); clear HC
  | Impl: forall (_ : ?Cond), _ |- _ => match goal with
      | p: Cond |- _ => specialize (Impl p)
      end
  end.

Ltac gather_vars :=
  let A := gather_vars_with (fun x : vars      => x         ) in
  let B := gather_vars_with (fun x : var       => \{ x }    ) in
  let C := gather_vars_with (fun x : ctx       => dom x     ) in
  let D := gather_vars_with (fun x : sto       => dom x     ) in
  let E := gather_vars_with (fun x : avar      => fv_avar  x) in
  let F := gather_vars_with (fun x : trm       => fv_trm   x) in
  let G := gather_vars_with (fun x : def       => fv_def   x) in
  let H := gather_vars_with (fun x : defs      => fv_defs  x) in
  let I := gather_vars_with (fun x : typ       => fv_typ   x) in
  let J := gather_vars_with (fun x : dec       => fv_dec   x) in
  let K := gather_vars_with (fun x : decs      => fv_decs  x) in
  constr:(A \u B \u C \u D \u E \u F \u G \u H \u I \u J \u K).

Ltac pick_fresh x :=
  let L := gather_vars in (pick_fresh_gen L x).

Tactic Notation "apply_fresh" constr(T) "as" ident(x) :=
  apply_fresh_base T gather_vars x.

Hint Constructors subtyp.
Hint Constructors subdec.


(* ###################################################################### *)
(** ** Library extensions *)

Lemma fresh_push_eq_inv: forall A x a (E: env A),
  x # (E & x ~ a) -> False.
Proof.
  intros. rewrite dom_push in H. false H. rewrite in_union.
  left. rewrite in_singleton. reflexivity.
Qed.

Definition vars_empty: vars := \{}. (* because tactic [exists] cannot infer type var *)


(* ###################################################################### *)
(** ** Definition of var-by-var substitution *)

(** Note that substitution is not part of the definitions, because for the
    definitions, opening is sufficient. For the proofs, however, we also
    need substitution, but only var-by-var substitution, not var-by-term
    substitution. That's why we don't need a judgment asserting that a term
    is locally closed. *)

Fixpoint subst_avar (z: var) (u: var) (a: avar) { struct a } : avar :=
  match a with
  | avar_b i => avar_b i
  | avar_f x => If x = z then (avar_f u) else (avar_f x)
  end.

Definition subst_pth (z: var) (u: var) (p: pth) : pth :=
  match p with
  | pth_var a => pth_var (subst_avar z u a)
  end.

Fixpoint subst_typ (z: var) (u: var) (T: typ) { struct T } : typ :=
  match T with
  | typ_top     => typ_top
  | typ_bot     => typ_bot
  | typ_bind Ds => typ_bind (subst_decs z u Ds)
  | typ_sel p L => typ_sel (subst_pth z u p) L
  end
with subst_dec (z: var) (u: var) (D: dec) { struct D } : dec :=
  match D with
  | dec_typ T U => dec_typ (subst_typ z u T) (subst_typ z u U)
  | dec_fld T   => dec_fld (subst_typ z u T)
  | dec_mtd T U => dec_mtd (subst_typ z u T) (subst_typ z u U)
  end
with subst_decs (z: var) (u: var) (Ds: decs) { struct Ds } : decs :=
  match Ds with
  | decs_nil          => decs_nil
  | decs_cons n D Ds' => decs_cons n (subst_dec z u D) (subst_decs z u Ds')
  end.

Fixpoint subst_trm (z: var) (u: var) (t: trm) : trm :=
  match t with
  | trm_var x        => trm_var (subst_avar z u x)
  | trm_new Ds ds    => trm_new (subst_decs z u Ds) (subst_defs z u ds)
  | trm_sel t l      => trm_sel (subst_trm z u t) l
  | trm_call t1 m t2 => trm_call (subst_trm z u t1) m (subst_trm z u t2)
  end
with subst_def (z: var) (u: var) (d: def) : def :=
  match d with
  | def_typ => def_typ
  | def_fld x => def_fld (subst_avar z u x)
  | def_mtd b => def_mtd (subst_trm z u b)
  end
with subst_defs (z: var) (u: var) (ds: defs) : defs :=
  match ds with
  | defs_nil => defs_nil
  | defs_cons n d rest => defs_cons n (subst_def z u d) (subst_defs z u rest)
  end.

Definition subst_ctx (z: var) (u: var) (G: ctx) : ctx := map (subst_typ z u) G.


(* ###################################################################### *)
(** ** Lemmas for var-by-var substitution *)

Lemma subst_fresh_avar: forall x y,
  (forall a: avar, x \notin fv_avar a -> subst_avar x y a = a).
Proof.
  intros. destruct* a. simpl. case_var*. simpls. notin_false.
Qed.

Lemma subst_fresh_pth: forall x y,
  (forall p: pth, x \notin fv_pth p -> subst_pth x y p = p).
Proof.
  intros. destruct p. simpl. f_equal. apply* subst_fresh_avar.
Qed.

Lemma subst_fresh_typ_dec_decs: forall x y,
  (forall T : typ , x \notin fv_typ  T  -> subst_typ  x y T  = T ) /\
  (forall d : dec , x \notin fv_dec  d  -> subst_dec  x y d  = d ) /\
  (forall ds: decs, x \notin fv_decs ds -> subst_decs x y ds = ds).
Proof.
  intros x y. apply typ_mutind; intros; simpls; f_equal*. apply* subst_fresh_pth.
Qed.

Lemma subst_fresh_trm_def_defs: forall x y,
  (forall t : trm , x \notin fv_trm  t  -> subst_trm  x y t  = t ) /\
  (forall d : def , x \notin fv_def  d  -> subst_def  x y d  = d ) /\
  (forall ds: defs, x \notin fv_defs ds -> subst_defs x y ds = ds).
Proof.
  intros x y. apply trm_mutind; intros; simpls; f_equal*.
  + apply* subst_fresh_avar.
  + apply* subst_fresh_typ_dec_decs.
  + apply* subst_fresh_avar.
Qed.

Definition subst_fvar(x y z: var): var := If x = z then y else z.

Lemma subst_open_commute_avar: forall x y u,
  (forall a: avar, forall n: nat,
    subst_avar x y (open_rec_avar n u a) 
    = open_rec_avar n (subst_fvar x y u) (subst_avar  x y a)).
Proof.
  intros. unfold subst_fvar, subst_avar, open_avar, open_rec_avar. destruct a.
  + repeat case_if; auto.
  + case_var*.
Qed.

Lemma subst_open_commute_pth: forall x y u,
  (forall p: pth, forall n: nat,
    subst_pth x y (open_rec_pth n u p) 
    = open_rec_pth n (subst_fvar x y u) (subst_pth x y p)).
Proof.
  intros. unfold subst_pth, open_pth, open_rec_pth. destruct p.
  f_equal. apply subst_open_commute_avar.
Qed.

(* "open and then substitute" = "substitute and then open" *)
Lemma subst_open_commute_typ_dec_decs: forall x y u,
  (forall t : typ, forall n: nat,
     subst_typ x y (open_rec_typ n u t)
     = open_rec_typ n (subst_fvar x y u) (subst_typ x y t)) /\
  (forall d : dec , forall n: nat, 
     subst_dec x y (open_rec_dec n u d)
     = open_rec_dec n (subst_fvar x y u) (subst_dec x y d)) /\
  (forall ds: decs, forall n: nat, 
     subst_decs x y (open_rec_decs n u ds)
     = open_rec_decs n (subst_fvar x y u) (subst_decs x y ds)).
Proof.
  intros. apply typ_mutind; intros; simpl; f_equal*. apply subst_open_commute_pth.
Qed.

(* "open and then substitute" = "substitute and then open" *)
Lemma subst_open_commute_trm_def_defs: forall x y u,
  (forall t : trm, forall n: nat,
     subst_trm x y (open_rec_trm n u t)
     = open_rec_trm n (subst_fvar x y u) (subst_trm x y t)) /\
  (forall d : def , forall n: nat, 
     subst_def x y (open_rec_def n u d)
     = open_rec_def n (subst_fvar x y u) (subst_def x y d)) /\
  (forall ds: defs, forall n: nat, 
     subst_defs x y (open_rec_defs n u ds)
     = open_rec_defs n (subst_fvar x y u) (subst_defs x y ds)).
Proof.
  intros. apply trm_mutind; intros; simpl; f_equal*.
  + apply* subst_open_commute_avar.
  + apply* subst_open_commute_typ_dec_decs.
  + apply* subst_open_commute_avar.
Qed.

Lemma subst_open_commute_trm: forall x y u t,
  subst_trm x y (open_trm u t) = open_trm (subst_fvar x y u) (subst_trm x y t).
Proof.
  intros. apply* subst_open_commute_trm_def_defs.
Qed.

Lemma subst_open_commute_defs: forall x y u ds,
  subst_defs x y (open_defs u ds) = open_defs (subst_fvar x y u) (subst_defs x y ds).
Proof.
  intros. apply* subst_open_commute_trm_def_defs.
Qed.

Lemma subst_open_commute_typ: forall x y u T,
  subst_typ x y (open_typ u T) = open_typ (subst_fvar x y u) (subst_typ x y T).
Proof.
  intros. apply* subst_open_commute_typ_dec_decs.
Qed.

Lemma subst_open_commute_dec: forall x y u D,
  subst_dec x y (open_dec u D) = open_dec (subst_fvar x y u) (subst_dec x y D).
Proof.
  intros. apply* subst_open_commute_typ_dec_decs.
Qed.

Lemma subst_open_commute_decs: forall x y u Ds,
  subst_decs x y (open_decs u Ds) = open_decs (subst_fvar x y u) (subst_decs x y Ds).
Proof.
  intros. apply* subst_open_commute_typ_dec_decs.
Qed.

(* "Introduce a substitution after open": Opening a term t with a var u is the
   same as opening t with x and then replacing x by u. *)
Lemma subst_intro_trm: forall x u t, x \notin (fv_trm t) ->
  open_trm u t = subst_trm x u (open_trm x t).
Proof.
  introv Fr. unfold open_trm. rewrite* subst_open_commute_trm.
  destruct (@subst_fresh_trm_def_defs x u) as [Q _]. rewrite* (Q t).
  unfold subst_fvar. case_var*.
Qed.

Lemma subst_intro_defs: forall x u ds, x \notin (fv_defs ds) ->
  open_defs u ds = subst_defs x u (open_defs x ds).
Proof.
  introv Fr. unfold open_trm. rewrite* subst_open_commute_defs.
  destruct (@subst_fresh_trm_def_defs x u) as [_ [_ Q]]. rewrite* (Q ds).
  unfold subst_fvar. case_var*.
Qed.

Lemma subst_intro_typ: forall x u T, x \notin (fv_typ T) ->
  open_typ u T = subst_typ x u (open_typ x T).
Proof.
  introv Fr. unfold open_typ. rewrite* subst_open_commute_typ.
  destruct (@subst_fresh_typ_dec_decs x u) as [Q _]. rewrite* (Q T).
  unfold subst_fvar. case_var*.
Qed.

Lemma subst_intro_decs: forall x u Ds, x \notin (fv_decs Ds) ->
  open_decs u Ds = subst_decs x u (open_decs x Ds).
Proof.
  introv Fr. unfold open_trm. rewrite* subst_open_commute_decs.
  destruct (@subst_fresh_typ_dec_decs x u) as [_ [_ Q]]. rewrite* (Q Ds).
  unfold subst_fvar. case_var*.
Qed.


(* ###################################################################### *)
(** ** Helper lemmas for definition/declaration lists *)

Lemma defs_has_fld_sync: forall n d ds,
  defs_has ds (label_fld n) d -> exists x, d = (def_fld x).
Proof.
  introv Hhas. induction ds; unfolds defs_has, get_def. 
  + discriminate.
  + case_if.
    - inversions Hhas. unfold label_for_def in H. destruct* d; discriminate.
    - apply* IHds.
Qed.

Lemma defs_has_mtd_sync: forall n d ds,
  defs_has ds (label_mtd n) d -> exists e, d = (def_mtd e).
Proof.
  introv Hhas. induction ds; unfolds defs_has, get_def. 
  + discriminate.
  + case_if.
    - inversions Hhas. unfold label_for_def in H. destruct* d; discriminate.
    - apply* IHds.
Qed.

Lemma decs_has_typ_sync: forall n D Ds,
  decs_has Ds (label_typ n) D -> exists Lo Hi, D = (dec_typ Lo Hi).
Proof.
  introv Hhas. induction Ds; unfolds decs_has, get_dec. 
  + discriminate.
  + case_if.
    - inversions Hhas. unfold label_for_dec in H. destruct* D; discriminate.
    - apply* IHDs.
Qed.

Lemma decs_has_fld_sync: forall n d ds,
  decs_has ds (label_fld n) d -> exists x, d = (dec_fld x).
Proof.
  introv Hhas. induction ds; unfolds decs_has, get_dec. 
  + discriminate.
  + case_if.
    - inversions Hhas. unfold label_for_dec in H. destruct* d; discriminate.
    - apply* IHds.
Qed.

Lemma decs_has_mtd_sync: forall n d ds,
  decs_has ds (label_mtd n) d -> exists T U, d = (dec_mtd T U).
Proof.
  introv Hhas. induction ds; unfolds decs_has, get_dec. 
  + discriminate.
  + case_if.
    - inversions Hhas. unfold label_for_dec in H. destruct* d; discriminate.
    - apply* IHds.
Qed.

Lemma get_def_cons : forall l n d ds,
  get_def l (defs_cons n d ds) = If l = (label_for_def n d) then Some d else get_def l ds.
Proof.
  intros. unfold get_def. case_if~.
Qed.

Lemma get_dec_cons : forall l n D Ds,
  get_dec l (decs_cons n D Ds) = If l = (label_for_dec n D) then Some D else get_dec l Ds.
Proof.
  intros. unfold get_dec. case_if~.
Qed.


(* ###################################################################### *)
(** ** Trivial inversion lemmas *)

(*
Lemma decs_has_preserves_sub_0: forall G Ds1 Ds2 l D1 D2,
  subdecs G Ds1 Ds2 ->
  decs_has Ds1 l D1 ->
  decs_has Ds2 l D2 ->
  subdec G D1 D2.
Proof.
  introv Sds. gen l D1 D2. induction Sds; introv Has1 Has2.
  + inversion Has2.
  + unfold decs_has, get_dec in Has2. fold get_dec in Has2. case_if.
    - inversions Has2. unfold decs_has in H, Has1.
      rewrite Has1 in H. inversions H. assumption.
    - apply* IHSds.
  + destruct l.
    - destruct (decs_has_typ_sync Has1) as [Lo1 [Hi1 Eq]]. subst.
      destruct (decs_has_typ_sync Has2) as [Lo2 [Hi2 Eq]]. subst.
      lets Sds: (subdecs_inv H H0).
      apply (subdec_inv Sds Has1 Has2).
    - destruct (decs_has_fld_sync Has1) as [T1 Eq]. subst.
      destruct (decs_has_fld_sync Has2) as [T2 Eq]. subst.
      lets Sds: (subdecs_inv H H0).
      apply (subdec_inv Sds Has1 Has2).
    - destruct (decs_has_mtd_sync Has1) as [T1 [U1 Eq]]. subst.
      destruct (decs_has_mtd_sync Has2) as [T2 [U2 Eq]]. subst.
      lets Sds: (subdecs_inv H H0).
      apply (subdec_inv Sds Has1 Has2).
Qed.

Print Assumptions decs_has_preserves_sub_0.

Lemma invert_subdec_typ_sync_left: forall G D T2 U2,
   subdec G D (dec_typ T2 U2) ->
   exists T1 U1, D = (dec_typ T1 U1) /\
                 subtyp G T2 T1 /\
                 subtyp G U1 U2.
Proof.
  introv Sd. inversions Sd.
  + exists Lo1 Hi1. apply (conj eq_refl). auto.
  + destruct l.
    - destruct (decs_has_typ_sync H0) as [Lo1 [Hi1 Eq]]. subst.
      destruct (decs_has_typ_sync H1) as [Lo2 [Hi2 Eq]]. inversions Eq.
      lets Sd: (decs_has_preserves_sub_0 H H0 H1).

Qed.

Lemma invert_subdec_fld_sync_left: forall G D T2,
   subdec G D (dec_fld T2) ->
   exists T1, D = (dec_fld T1) /\
              subtyp G T1 T2.
Proof.
  introv Sd. inversions Sd. exists T1. apply (conj eq_refl). assumption.
Qed.

Lemma invert_subdec_mtd_sync_left: forall G D T2 U2,
   subdec G D (dec_mtd T2 U2) ->
   exists T1 U1, D = (dec_mtd T1 U1) /\
                 subtyp G T2 T1 /\
                 subtyp G U1 U2.
Proof.
  introv Sd. inversions Sd. exists S1 T1. apply (conj eq_refl). auto.
Qed.

*)

Lemma wf_sto_to_ok_s: forall s G,
  wf_sto s G -> ok s.
Proof. intros. induction H; jauto. Qed.

Lemma wf_sto_to_ok_G: forall s G,
  wf_sto s G -> ok G.
Proof. intros. induction H; jauto. Qed.

Hint Resolve wf_sto_to_ok_s wf_sto_to_ok_G.

Lemma ctx_binds_to_sto_binds: forall s G x T,
  wf_sto s G ->
  binds x T G ->
  exists o, binds x o s.
Proof.
  introv Wf Bi. gen x T Bi. induction Wf; intros.
  + false* binds_empty_inv.
  + unfolds binds. rewrite get_push in *. case_if.
    - eauto.
    - eauto.
Qed.

Lemma sto_binds_to_ctx_binds: forall s G x Ds ds,
  wf_sto s G ->
  binds x (object Ds ds) s ->
  binds x (typ_bind Ds) G.
Proof.
  introv Wf Bi. gen x Ds Bi. induction Wf; intros.
  + false* binds_empty_inv.
  + unfolds binds. rewrite get_push in *. case_if.
    - inversions Bi. reflexivity.
    - auto.
Qed.

Lemma sto_unbound_to_ctx_unbound: forall s G x,
  wf_sto s G ->
  x # s ->
  x # G.
Proof.
  introv Wf Ub_s.
  induction Wf.
  + auto.
  + destruct (classicT (x0 = x)) as [Eq | Ne].
    - subst. false (fresh_push_eq_inv Ub_s). 
    - auto.
Qed.

Lemma ctx_unbound_to_sto_unbound: forall s G x,
  wf_sto s G ->
  x # G ->
  x # s.
Proof.
  introv Wf Ub.
  induction Wf.
  + auto.
  + destruct (classicT (x0 = x)) as [Eq | Ne].
    - subst. false (fresh_push_eq_inv Ub). 
    - auto.
Qed.

Lemma invert_wf_sto: forall s G,
  wf_sto s G ->
    forall x ds Ds T,
      binds x (object Ds ds) s -> 
      binds x T G ->
      T = (typ_bind Ds) /\ exists G1 G2,
        G = G1 & x ~ typ_bind Ds & G2 /\ 
        ty_defs (G1 & x ~ typ_bind Ds) (open_defs x ds) (open_decs x Ds) /\
        (forall L S U, decs_has (open_decs x Ds) L (dec_typ S U) -> 
                       subtyp (G1 & x ~ typ_bind Ds) S U).
Proof.
  intros s G Wf. induction Wf; intros.
  + false* binds_empty_inv.
  + unfold binds in *. rewrite get_push in *.
    case_if.
    - inversions H3. inversions H4. split. reflexivity.
      exists G (@empty typ). rewrite concat_empty_r. auto.
    - specialize (IHWf x0 ds0 Ds0 T H3 H4).
      destruct IHWf as [EqDs [G1 [G2 [EqG [Ty F]]]]]. subst.
      apply (conj eq_refl).
      exists G1 (G2 & x ~ typ_bind Ds).
      rewrite concat_assoc.
      apply (conj eq_refl). auto.
Qed.

Lemma decs_has_preserves_sub_with_sync: forall G Ds1 Ds2 l D1 D2,
   subdecs G Ds1 Ds2 ->
   decs_has Ds1 l D1 ->
   decs_has Ds2 l D2 ->
   subdec G D1 D2 /\ (
   (exists Lo1 Hi1 Lo2 Hi2, D1 = dec_typ Lo1 Hi1 /\ D2 = dec_typ Lo2 Hi2)
\/ (exists T1 T2, D1 = dec_fld T1 /\ D2 = dec_fld T2)
\/ (exists T1 U1 T2 U2, D1 = dec_mtd T1 U1 /\ D2 = dec_mtd T2 U2)).
Proof.
  introv Sds. gen l D1 D2. induction Sds; introv Has1 Has2.
  + inversion Has2.
  + unfold decs_has, get_dec in Has2. fold get_dec in Has2. case_if.
    - inversions Has2. unfold decs_has in H, Has1.
      rewrite Has1 in H. inversions H. apply (conj H0).
      destruct D3; simpl in Has1.
      * destruct (decs_has_typ_sync Has1) as [Lo1 [Hi1 Eq]]. subst.
        left. do 4 eexists. eauto.
      * destruct (decs_has_fld_sync Has1) as [T1 Eq]. subst.
        right. left. eauto.
      * destruct (decs_has_mtd_sync Has1) as [T1 [U1 Eq]]. subst.
        right. right. do 4 eexists. eauto.
    - apply* IHSds.
(*
  + destruct l.
    - destruct (decs_has_typ_sync Has1) as [Lo1 [Hi1 Eq]]. subst.
      destruct (decs_has_typ_sync Has2) as [Lo2 [Hi2 Eq]]. subst.
      lets Sds: (subdecs_inv H H0).
      apply (conj (subdec_inv Sds Has1 Has2)).
      left. do 4 eexists. eauto.
    - destruct (decs_has_fld_sync Has1) as [T1 Eq]. subst.
      destruct (decs_has_fld_sync Has2) as [T2 Eq]. subst.
      lets Sds: (subdecs_inv H H0).
      apply (conj (subdec_inv Sds Has1 Has2)).
      right. left. eauto.
    - destruct (decs_has_mtd_sync Has1) as [T1 [U1 Eq]]. subst.
      destruct (decs_has_mtd_sync Has2) as [T2 [U2 Eq]]. subst.
      lets Sds: (subdecs_inv H H0).
      apply (conj (subdec_inv Sds Has1 Has2)).
      right. right. do 4 eexists. eauto.
*)
Qed.

Lemma subdec_sync: forall G D1 D2,
   subdec G D1 D2 ->
   (exists Lo1 Hi1 Lo2 Hi2, D1 = dec_typ Lo1 Hi1 /\ D2 = dec_typ Lo2 Hi2)
\/ (exists T1 T2, D1 = dec_fld T1 /\ D2 = dec_fld T2)
\/ (exists T1 U1 T2 U2, D1 = dec_mtd T1 U1 /\ D2 = dec_mtd T2 U2).
Proof.
  introv Sd. inversions Sd.
  + left. do 4 eexists. eauto.
  + right. left. eauto.
  + right. right. do 4 eexists. eauto.
Qed.

Ltac subdec_sync_for Hyp :=
  let Lo1 := fresh "Lo1" in
  let Hi1 := fresh "Hi1" in
  let Lo2 := fresh "Lo2" in
  let Hi2 := fresh "Hi2" in
  let Eq1 := fresh "Eq1" in
  let Eq2 := fresh "Eq2" in
  let T1  := fresh "T1"  in
  let T2  := fresh "T2"  in
  let U1  := fresh "U1"  in
  let U2  := fresh "U2"  in
  destruct (subdec_sync Hyp) as [[Lo1 [Hi1 [Lo2 [Hi2 [Eq1 Eq2]]]]] 
    | [[T1 [T2 [Eq1 Eq2]]] | [T1 [U1 [T2 [U2 [Eq1 Eq2]]]]]]].

Lemma subdec_to_label_for_eq: forall G D1 D2 n,
  subdec G D1 D2 ->
  (label_for_dec n D1) = (label_for_dec n D2).
Proof.
  introv Sd. subdec_sync_for Sd; subst; reflexivity.
Qed.

(*
Lemma invert_subdecs_push: forall G Ds1 Ds2 n D2,
  subdecs G Ds1 (decs_cons n D2 Ds2) -> 
    exists D1, decs_has Ds1 (label_for_dec n D2) D1
            /\ subdec G D1 D2
            /\ subdecs G Ds1 Ds2.
Proof.
  intros. inversions H. eauto.
Qed.
*)

Lemma ty_def_to_label_for_eq: forall G d D n, 
  ty_def G d D ->
  label_for_def n d = label_for_dec n D.
Proof.
  intros. inversions H; reflexivity.
Qed.

Lemma extract_ty_def_from_ty_defs: forall G l d ds D Ds,
  ty_defs G ds Ds ->
  defs_has ds l d ->
  decs_has Ds l D ->
  ty_def G d D.
Proof.
  introv HdsDs. induction HdsDs.
  + intros. inversion H.
  + introv dsHas DsHas. unfolds defs_has, decs_has, get_def, get_dec. 
    rewrite (ty_def_to_label_for_eq n H) in dsHas. case_if.
    - inversions dsHas. inversions DsHas. assumption.
    - apply* IHHdsDs.
Qed.

Lemma invert_ty_mtd_inside_ty_defs: forall G ds Ds m S T body,
  ty_defs G ds Ds ->
  defs_has ds (label_mtd m) (def_mtd body) ->
  decs_has Ds (label_mtd m) (dec_mtd S T) ->
  (* conclusion is the premise needed to construct a ty_mtd: *)
  exists L, forall x, x \notin L -> ty_trm (G & x ~ S) (open_trm x body) T.
Proof.
  introv HdsDs dsHas DsHas.
  lets H: (extract_ty_def_from_ty_defs HdsDs dsHas DsHas).
  inversions* H. 
Qed.

Lemma invert_ty_fld_inside_ty_defs: forall G ds Ds l v T,
  ty_defs G ds Ds ->
  defs_has ds (label_fld l) (def_fld v) ->
  decs_has Ds (label_fld l) (dec_fld T) ->
  (* conclusion is the premise needed to construct a ty_fld: *)
  ty_trm G (trm_var v) T.
Proof.
  introv HdsDs dsHas DsHas.
  lets H: (extract_ty_def_from_ty_defs HdsDs dsHas DsHas).
  inversions* H. 
Qed.

Lemma decs_has_to_defs_has: forall G l ds Ds D,
  ty_defs G ds Ds ->
  decs_has Ds l D ->
  exists d, defs_has ds l d.
Proof.
  introv Ty Bi. induction Ty; unfolds decs_has, get_dec. 
  + discriminate.
  + unfold defs_has. folds get_dec. rewrite get_def_cons. case_if.
    - exists d. reflexivity.
    - rewrite <- (ty_def_to_label_for_eq n H) in Bi. case_if. apply (IHTy Bi).
Qed.

Print Assumptions decs_has_to_defs_has.

Lemma defs_has_to_decs_has: forall G l ds Ds d,
  ty_defs G ds Ds ->
  defs_has ds l d ->
  exists D, decs_has Ds l D.
Proof.
  introv Ty dsHas. induction Ty; unfolds defs_has, get_def. 
  + discriminate.
  + unfold decs_has. folds get_def. rewrite get_dec_cons. case_if.
    - exists D. reflexivity.
    - rewrite -> (ty_def_to_label_for_eq n H) in dsHas. case_if. apply (IHTy dsHas).
Qed.

Print Assumptions defs_has_to_decs_has.

Lemma label_for_dec_open: forall z D n,
  label_for_dec n (open_dec z D) = label_for_dec n D.
Proof.
  intros. destruct D; reflexivity.
Qed.

(* The converse does not hold because
   [(open_dec z D1) = (open_dec z D2)] does not imply [D1 = D2]. *)
Lemma decs_has_open: forall Ds l D z,
  decs_has Ds l D -> decs_has (open_decs z Ds) l (open_dec z D).
Proof.
  introv Has. induction Ds.
  + inversion Has.
  + unfold open_decs, open_rec_decs. fold open_rec_decs. fold open_rec_dec.
    unfold decs_has, get_dec. case_if.
    - unfold decs_has, get_dec in Has. rewrite label_for_dec_open in Has. case_if.
      inversions Has. reflexivity.
    - fold get_dec. apply IHDs. unfold decs_has, get_dec in Has.
      rewrite label_for_dec_open in H. case_if. apply Has.
Qed.


(* ###################################################################### *)
(** ** Weakening *)

Lemma weakening:
   (forall G T Ds, exp G T Ds -> forall G1 G2 G3,
      G = G1 & G3 ->
      ok (G1 & G2 & G3) ->
      exp (G1 & G2 & G3) T Ds)
/\ (forall G t l d, has G t l d -> forall G1 G2 G3,
      G = G1 & G3 ->
      ok (G1 & G2 & G3) ->
      has (G1 & G2 & G3) t l d)
/\ (forall G T1 T2, subtyp G T1 T2 -> forall G1 G2 G3,
      G = G1 & G3 ->
      ok (G1 & G2 & G3) ->
      subtyp (G1 & G2 & G3) T1 T2)
/\ (forall G D1 D2, subdec G D1 D2 -> forall G1 G2 G3,
      G = G1 & G3 ->
      ok (G1 & G2 & G3) ->
      subdec (G1 & G2 & G3) D1 D2)
/\ (forall G Ds1 Ds2, subdecs G Ds1 Ds2 -> forall G1 G2 G3,
      G = G1 & G3 ->
      ok (G1 & G2 & G3) ->
      subdecs (G1 & G2 & G3) Ds1 Ds2)
/\ (forall G t T, ty_trm G t T -> forall G1 G2 G3,
      G = G1 & G3 ->
      ok (G1 & G2 & G3) ->
      ty_trm (G1 & G2 & G3) t T)
/\ (forall G d D, ty_def G d D -> forall G1 G2 G3,
      G = G1 & G3 ->
      ok (G1 & G2 & G3) ->
      ty_def (G1 & G2 & G3) d D)
/\ (forall G ds Ds, ty_defs G ds Ds -> forall G1 G2 G3,
      G = G1 & G3 ->
      ok (G1 & G2 & G3) ->
      ty_defs (G1 & G2 & G3) ds Ds).
Proof.
  apply ty_mutind.
  + (* case exp_top *)
    intros. apply exp_top.
  + (* case exp_bind *)
    intros. apply exp_bind.
  + (* case exp_sel *)
    intros. apply* exp_sel.
  + (* case has_trm *)
    intros. apply* has_trm.
  + (* case has_var *)
    intros. apply* has_var.
  + (* case subtyp_refl *)
    introv Hok123 Heq; subst.
    apply (subtyp_refl _ _).
  + (* case subtyp_top *)
    introv Hok123 Heq; subst.
    apply (subtyp_top _ _).
  + (* case subtyp_bot *)
    introv Hok123 Heq; subst.
    apply (subtyp_bot _ _).
  + (* case subtyp_bind *)
    introv Hc IH Hok123 Heq; subst.
    apply_fresh subtyp_bind as z.
    rewrite <- concat_assoc.
    refine (IH z _ G1 G2 (G3 & z ~ typ_bind Ds1) _ _).
    - auto.
    - rewrite <- concat_assoc. reflexivity.
    - rewrite concat_assoc. auto.
  + (* case subtyp_asel_l *)
    intros. subst. apply* subtyp_sel_l.
  + (* case subtyp_asel_r *)
    intros. subst. apply* subtyp_sel_r.
  + (* case subtyp_trans *)
    intros. subst. apply* subtyp_trans.
  + (* case subtyp_inv_typ_lo *)
    intros. subst. apply* subtyp_inv_typ_lo.
  + (* case subtyp_inv_typ_hi *)
    intros. subst. apply* subtyp_inv_typ_hi.
  + (* case subtyp_inv_fld *)
    intros. subst. apply* subtyp_inv_fld.
  + (* case subtyp_inv_mtd_arg *)
    intros. subst. apply* subtyp_inv_mtd_arg.
  + (* case subtyp_inv_mtd_ret *)
    intros. subst. apply* subtyp_inv_mtd_ret.
  + (* case subdec_typ *)
    intros.
    apply subdec_typ; gen G1 G2 G3; assumption.
  + (* case subdec_fld *)
    intros.
    apply subdec_fld; gen G1 G2 G3; assumption.
  + (* case subdec_mtd *)
    intros.
    apply subdec_mtd; gen G1 G2 G3; assumption.
  + (* case subdecs_empty *)
    intros.
    apply subdecs_empty.
  + (* case subdecs_push *)
    introv Hb Hsd IHsd Hsds IHsds Hok123 Heq.
    apply (subdecs_push n Hb).
    apply (IHsd _ _ _ Hok123 Heq).
    apply (IHsds _ _ _ Hok123 Heq).
(*
  + (* case subdecs_inv *)
    intros. subst. apply subdecs_inv.
    - apply* H.
    - apply* H0.
*)
  + (* case ty_var *)
    intros. subst. apply ty_var. apply* binds_weaken.
  + (* case ty_sel *)
    intros. subst. apply* ty_sel.
  + (* case ty_call *)
    intros. subst. apply* ty_call.
  + (* case ty_new *)
    intros L G ds Ds Tyds IHTyds F IHF G1 G2 G3 Eq Ok. subst.
    apply_fresh ty_new as x; assert (xL: x \notin L) by auto.
    - specialize (IHTyds x xL G1 G2 (G3 & x ~ typ_bind Ds)).
      rewrite <- concat_assoc. apply IHTyds.
      * rewrite concat_assoc. reflexivity.
      * rewrite concat_assoc. auto.
    - introv Has. specialize (IHF x xL M S U). rewrite <- concat_assoc. apply IHF.
      * auto.
      * rewrite concat_assoc. reflexivity.
      * rewrite concat_assoc. auto.
  + (* case ty_sbsm *)
    intros. apply ty_sbsm with T.
    - apply* H.
    - apply* H0.
  + (* case ty_typ *)
    intros. apply ty_typ. 
  + (* case ty_fld *)
    intros. apply* ty_fld.
  + (* case ty_mtd *) 
    intros. subst. rename H into IH.
    apply_fresh ty_mtd as x.
    rewrite <- concat_assoc.
    refine (IH x _ G1 G2 (G3 & x ~ S) _ _).
    - auto.
    - symmetry. apply concat_assoc.
    - rewrite concat_assoc. auto.
  + (* case ty_dsnil *) 
    intros. apply ty_dsnil.
  + (* case ty_dscons *) 
    intros. apply* ty_dscons.
Qed.

Print Assumptions weakening.

Lemma weaken_exp_middle: forall G1 G2 G3 T Ds,
  ok (G1 & G2 & G3) -> exp (G1 & G3) T Ds -> exp (G1 & G2 & G3) T Ds.
Proof.
  intros. apply* weakening.
Qed.

Lemma weaken_exp_end: forall G1 G2 T Ds,
  ok (G1 & G2) -> exp G1 T Ds -> exp (G1 & G2) T Ds.
Proof.
  introv Ok Exp.
  assert (Eq1: G1 = G1 & empty) by (rewrite concat_empty_r; reflexivity).
  assert (Eq2: G1 & G2 = G1 & G2 & empty) by (rewrite concat_empty_r; reflexivity).
  rewrite Eq1 in Exp. rewrite Eq2 in Ok. rewrite Eq2.
  apply (weaken_exp_middle Ok Exp).
Qed.

Lemma weaken_subtyp_middle: forall G1 G2 G3 S U,
  ok (G1 & G2 & G3) -> 
  subtyp (G1      & G3) S U ->
  subtyp (G1 & G2 & G3) S U.
Proof.
  destruct weakening as [_ [_ [W _]]].
  introv Hok123 Hst.
  specialize (W (G1 & G3) S U Hst).
  specialize (W G1 G2 G3 eq_refl Hok123).
  apply W.
Qed.

Lemma env_add_empty: forall (P: ctx -> Prop) (G: ctx), P G -> P (G & empty).
Proof.
  intros.
  assert ((G & empty) = G) by apply concat_empty_r.
  rewrite -> H0. assumption.
Qed.  

Lemma env_remove_empty: forall (P: ctx -> Prop) (G: ctx), P (G & empty) -> P G.
Proof.
  intros.
  assert ((G & empty) = G) by apply concat_empty_r.
  rewrite <- H0. assumption.
Qed.

Lemma weaken_subtyp_end: forall G1 G2 S U,
  ok (G1 & G2) -> 
  subtyp G1        S U ->
  subtyp (G1 & G2) S U.
Proof.
  introv Hok Hst.
  apply (env_remove_empty (fun G0 => subtyp G0 S U) (G1 & G2)).
  apply weaken_subtyp_middle.
  apply (env_add_empty (fun G0 => ok G0) (G1 & G2) Hok).
  apply (env_add_empty (fun G0 => subtyp G0 S U) G1 Hst).
Qed.

Lemma weaken_has_end: forall G1 G2 t l d,
  ok (G1 & G2) -> has G1 t l d -> has (G1 & G2) t l d.
Proof.
  intros.
  destruct weakening as [_ [W _]].
  rewrite <- (concat_empty_r (G1 & G2)).
  apply (W (G1 & empty)); rewrite* concat_empty_r.
Qed.

Lemma weaken_ty_trm_end: forall G1 G2 e T,
  ok (G1 & G2) -> ty_trm G1 e T -> ty_trm (G1 & G2) e T.
Proof.
  intros.
  destruct weakening as [_ [_ [_ [_ [_ [W _]]]]]].
  rewrite <- (concat_empty_r (G1 & G2)).
  apply (W (G1 & empty)); rewrite* concat_empty_r.
Qed.

Lemma weaken_ty_def_end: forall G1 G2 i d,
  ok (G1 & G2) -> ty_def G1 i d -> ty_def (G1 & G2) i d.
Proof.
  intros.
  destruct weakening as [_ [_ [_ [_ [_ [_ [W _]]]]]]].
  rewrite <- (concat_empty_r (G1 & G2)).
  apply (W (G1 & empty)); rewrite* concat_empty_r.
Qed.

Lemma weaken_ty_defs_end: forall G1 G2 is Ds,
  ok (G1 & G2) -> ty_defs G1 is Ds -> ty_defs (G1 & G2) is Ds.
Proof.
  intros.
  destruct weakening as [_ [_ [_ [_ [_ [_ [_ W]]]]]]].
  rewrite <- (concat_empty_r (G1 & G2)).
  apply (W (G1 & empty)); rewrite* concat_empty_r.
Qed.

Lemma weaken_ty_trm_middle: forall G1 G2 G3 t T,
  ok (G1 & G2 & G3) -> ty_trm (G1 & G3) t T -> ty_trm (G1 & G2 & G3) t T.
Proof.
  intros. apply* weakening.
Qed.

Lemma weaken_ty_def_middle: forall G1 G2 G3 d D,
  ty_def (G1 & G3) d D -> ok (G1 & G2 & G3) -> ty_def (G1 & G2 & G3) d D.
Proof.
  intros. apply* weakening.
Qed.

Lemma weaken_ty_defs_middle: forall G1 G2 G3 ds Ds,
  ty_defs (G1 & G3) ds Ds -> ok (G1 & G2 & G3) -> ty_defs (G1 & G2 & G3) ds Ds.
Proof.
  intros. apply* weakening.
Qed.


(* ###################################################################### *)
(** ** The substitution principle *)

(*

without dependent types:

                  G, x: S |- e : T      G |- u : S
                 ----------------------------------
                            G |- [u/x]e : T

with dependent types:

                  G1, x: S, G2 |- t : T      G1 |- y : S
                 ---------------------------------------
                      G1, [y/x]G2 |- [y/x]t : [y/x]T


Note that in general, u is a term, but for our purposes, it suffices to consider
the special case where u is a variable.
*)

Lemma subst_label_for_dec: forall n x y D,
  label_for_dec n (subst_dec x y D) = label_for_dec n D.
Proof.
  intros. destruct D; reflexivity.
Qed.

Lemma subst_decs_has: forall x y Ds l D,
  decs_has Ds l D ->
  decs_has (subst_decs x y Ds) l (subst_dec x y D).
Proof.
  introv Has. induction Ds.
  + inversion Has.
  + unfold subst_decs, decs_has, get_dec. fold subst_decs subst_dec get_dec.
    rewrite subst_label_for_dec.
    unfold decs_has, get_dec in Has. fold get_dec in Has. case_if.
    - inversions Has. reflexivity.
    - apply* IHDs.
Qed.

Lemma subst_binds: forall x y v T G,
  binds v T G ->
  binds v (subst_typ x y T) (subst_ctx x y G).
Proof.
  introv Bi. unfold subst_ctx. apply binds_map. exact Bi.
Qed.

Lemma subst_principles: forall y S,
   (forall G T Ds, exp G T Ds -> forall G1 G2 x, G = G1 & x ~ S & G2 ->
      ty_trm G1 (trm_var (avar_f y)) S ->
      ok (G1 & x ~ S & G2) ->
      exp (G1 & (subst_ctx x y G2)) (subst_typ x y T) (subst_decs x y Ds))
/\ (forall G t l D, has G t l D -> forall G1 G2 x,
     G = (G1 & (x ~ S) & G2) ->
     ty_trm G1 (trm_var (avar_f y)) S ->
     ok (G1 & (x ~ S) & G2) ->
     has (G1 & (subst_ctx x y G2)) (subst_trm x y t) l (subst_dec x y D))
/\ (forall G T U, subtyp G T U -> forall G1 G2 x,
     G = (G1 & (x ~ S) & G2) ->
     ty_trm G1 (trm_var (avar_f y)) S ->
     ok (G1 & (x ~ S) & G2) ->
     subtyp (G1 & (subst_ctx x y G2)) (subst_typ x y T) (subst_typ x y U))
/\ (forall G D1 D2, subdec G D1 D2 -> forall G1 G2 x,
     G = (G1 & (x ~ S) & G2) ->
     ty_trm G1 (trm_var (avar_f y)) S ->
     ok (G1 & (x ~ S) & G2) ->
     subdec (G1 & (subst_ctx x y G2)) (subst_dec x y D1) (subst_dec x y D2))
/\ (forall G Ds1 Ds2, subdecs G Ds1 Ds2 -> forall G1 G2 x,
     G = (G1 & (x ~ S) & G2) ->
     ty_trm G1 (trm_var (avar_f y)) S ->
     ok (G1 & (x ~ S) & G2) ->
     subdecs (G1 & (subst_ctx x y G2)) (subst_decs x y Ds1) (subst_decs x y Ds2))
/\ (forall G t T, ty_trm G t T -> forall G1 G2 x,
     G = (G1 & (x ~ S) & G2) ->
     ty_trm G1 (trm_var (avar_f y)) S ->
     ok (G1 & (x ~ S) & G2) ->
     ty_trm (G1 & (subst_ctx x y G2)) (subst_trm x y t) (subst_typ x y T))
/\ (forall G d D, ty_def G d D -> forall G1 G2 x,
     G = (G1 & (x ~ S) & G2) ->
     ty_trm G1 (trm_var (avar_f y)) S ->
     ok (G1 & (x ~ S) & G2) ->
     ty_def (G1 & (subst_ctx x y G2)) (subst_def x y d) (subst_dec x y D))
/\ (forall G ds Ds, ty_defs G ds Ds -> forall G1 G2 x,
     G = (G1 & (x ~ S) & G2) ->
     ty_trm G1 (trm_var (avar_f y)) S ->
     ok (G1 & (x ~ S) & G2) ->
     ty_defs (G1 & (subst_ctx x y G2)) (subst_defs x y ds) (subst_decs x y Ds)).
Proof.
  intros y S. apply ty_mutind.
  (* case exp_top *)
  + intros. simpl. apply exp_top.
  (* case exp_bind *)
  + intros. simpl. apply exp_bind.
  (* case exp_sel *)
  + intros G v L Lo Hi Ds Has IHHas Exp IHExp G1 G2 x EqG Tyy Ok. subst G.
    specialize (IHHas _ _ _ eq_refl Tyy Ok).
    specialize (IHExp _ _ _ eq_refl Tyy Ok).
    unfold subst_typ. unfold subst_pth. unfold subst_avar. case_if.
    - simpl in IHHas. case_if.
      apply (exp_sel IHHas IHExp).
    - simpl in IHHas. case_if.
      apply (exp_sel IHHas IHExp).
  + (* case has_trm *)
    intros G t T Ds l D Ty IHTy Exp IHExp Has Clo G1 G2 x EqG Bi Ok.
    subst G. specialize (IHTy _ _ _ eq_refl Bi Ok).
    apply has_trm with (subst_typ x y T) (subst_decs x y Ds).
    - exact IHTy.
    - apply* IHExp.
    - apply* subst_decs_has.
    - intro z. specialize (Clo z). admit.
  + (* case has_var *)
    intros G z T Ds l D Ty IHTy Exp IHExp Has G1 G2 x EqG Bi Ok.
    subst G. specialize (IHTy _ _ _ eq_refl Bi Ok). simpl in *. case_if.
    - (* case z = x *)
      rewrite (subst_open_commute_dec x y x D). unfold subst_fvar. case_if.
      apply has_var with (subst_typ x y T) (subst_decs x y Ds).
      * exact IHTy.
      * apply* IHExp.
      * apply (subst_decs_has x y Has).
    - (* case z <> x *)
      rewrite (subst_open_commute_dec x y z D). unfold subst_fvar. case_if.
      apply has_var with (subst_typ x y T) (subst_decs x y Ds).
      * exact IHTy.
      * apply* IHExp.
      * apply (subst_decs_has x y Has).
  + (* case subtyp_refl *)
    intros. simpl. case_if; apply subtyp_refl.
  + (* case subtyp_top *)
    intros. simpl. apply subtyp_top.
  + (* case subtyp_bot *)
    intros. simpl. apply subtyp_bot.
  + (* case subtyp_bind *)
    intros L G Ds1 Ds2 Sds IH G1 G2 x Eq Bi Ok. subst.
    apply_fresh subtyp_bind as z. fold subst_decs.
    assert (zL: z \notin L) by auto.
    specialize (IH z zL G1 (G2 & z ~ typ_bind Ds1) x).
    rewrite concat_assoc in IH.
    specialize (IH eq_refl Bi).
    unfold subst_ctx in IH. rewrite map_push in IH. simpl in IH.
    rewrite concat_assoc in IH.
    rewrite (subst_open_commute_decs x y z Ds1) in IH.
    rewrite (subst_open_commute_decs x y z Ds2) in IH.
    unfold subst_fvar in IH.
    assert (x <> z) by auto. case_if.
    unfold subst_ctx. apply IH. admit.
  + (* case subtyp_sel_l *)
    intros G v L Lo Hi Has IHHas G1 G2 x Eq Bi Ok. subst.
    specialize (IHHas _ _ _ eq_refl Bi Ok).
    simpl in *.
    case_if; apply (subtyp_sel_l IHHas).
  + (* case subtyp_sel_r *)
    intros G v L Lo Hi Has IHHas G1 G2 x Eq Bi Ok. subst.
    specialize (IHHas _ _ _ eq_refl Bi Ok).
    simpl in *.
    case_if; apply (subtyp_sel_r IHHas).
  + (* case subtyp_trans *)
    intros G T1 T2 T3 St12 IH12 St23 IH23 G1 G2 x Eq Bi Ok. subst.
    apply* subtyp_trans.
  + (* case subtyp_inv_typ_lo *)
    intros G T1 T2 Ds1 Ds2 l Lo1 Hi1 Lo2 Hi2 St IHSt Exp1 IHExp1 Exp2 IHExp2.
    intros Ds1Has Ds2Has G1 G2 x Eq Ty Ok. subst.
    apply subtyp_inv_typ_lo with (subst_typ x y T1) (subst_typ x y T2)
      (subst_decs x y Ds1) (subst_decs x y Ds2) l (subst_typ x y Hi1) (subst_typ x y Hi2).
    - apply* IHSt.
    - apply* IHExp1.
    - apply* IHExp2.
    - assert (Eq: (dec_typ (subst_typ x y Lo1) (subst_typ x y Hi1)
                = (subst_dec x y (dec_typ Lo1 Hi1)))) by reflexivity.
      rewrite Eq.
      apply* subst_decs_has.
    - assert (Eq: (dec_typ (subst_typ x y Lo2) (subst_typ x y Hi2)
                = (subst_dec x y (dec_typ Lo2 Hi2)))) by reflexivity.
      rewrite Eq.
      apply* subst_decs_has.
  (* other inv cases: similar *)
  + admit.
  + admit.
  + admit.
  + admit.
  (*
  + (* case subtyp_inv_typ_hi *)
    intros. subst.
    apply subtyp_inv_typ_hi with (subst_typ x y Lo1) (subst_typ x y Lo2).
    apply* H.
  + (* case subtyp_inv_fld *)
    intros. subst.
    apply subtyp_inv_fld. apply* H.
  + (* case subtyp_inv_mtd_arg *)
    intros. subst.
    apply subtyp_inv_mtd_arg with (subst_typ x y U1) (subst_typ x y U2).
    apply* H.
  + (* case subtyp_inv_mtd_ret *)
    intros. subst.
    apply subtyp_inv_mtd_ret with (subst_typ x y T1) (subst_typ x y T2).
    apply* H.
  *)
  + (* case subdec_typ *)
    intros. apply* subdec_typ.
  + (* case subdec_fld *)
    intros. apply* subdec_fld.
  + (* case subdec_mtd *)
    intros. apply* subdec_mtd.
  + (* case subdecs_empty *)
    intros. apply subdecs_empty.
  + (* case subdecs_push *)
    intros G n Ds1 Ds2 D1 D2 Has Sd IH1 Sds IH2 G1 G2 x Eq Bi Ok. subst.
    specialize (IH1 _ _ _ eq_refl Bi Ok).
    specialize (IH2 _ _ _ eq_refl Bi Ok).
    apply (subst_decs_has x y) in Has.
    rewrite <- (subst_label_for_dec n x y D2) in Has.
    apply subdecs_push with (subst_dec x y D1); 
      fold subst_dec; fold subst_decs; assumption.
  + (* case ty_var *)
    intros G z T Biz G1 G2 x EqG Biy Ok.
    subst G. unfold subst_trm, subst_avar. case_var.
    - (* case z = x *)
      assert (EqST: T = S) by apply (binds_middle_eq_inv Biz Ok). subst.
      assert (yG2: y # (subst_ctx x y G2)) by admit.
      assert (xG1: x # G1) by admit.
      assert (Eq: (subst_typ x y S) = S) by admit.
      rewrite Eq. 
      apply weaken_ty_trm_end.
      * unfold subst_ctx. auto.
      * assumption.
    - (* case z <> x *)
      apply ty_var. admit. (* TODO! *)
  (* case ty_sel *)
  + intros G t l T Has IH G1 G2 x Eq Bi Ok. apply* ty_sel.
  (* case ty_call *)
  + intros G t m U V u Has IHt Tyu IHu G1 G2 x Eq Bi Ok. apply* ty_call.
  (* case ty_new *)
  + intros L G ds Ds Tyds IHTyds F IHF G1 G2 x Eq Bi Ok. subst G.
    apply_fresh ty_new as z.
    - fold subst_defs.
      lets C: (@subst_open_commute_defs x y z ds).
      unfolds open_defs. unfold subst_fvar in C. case_var.
      rewrite <- C.
      lets D: (@subst_open_commute_decs x y z Ds).
      unfolds open_defs. unfold subst_fvar in D. case_var.
      rewrite <- D.
      rewrite <- concat_assoc.
      assert (zL: z \notin L) by auto.
      specialize (IHTyds z zL G1 (G2 & z ~ typ_bind Ds) x). rewrite concat_assoc in IHTyds.
      specialize (IHTyds eq_refl Bi).
      unfold subst_ctx in IHTyds. rewrite map_push in IHTyds. unfold subst_ctx.
      apply IHTyds. auto.
    - intros M Lo Hi Has.
      assert (zL: z \notin L) by auto. specialize (F z zL M Lo Hi).
      admit. (* TODO! *)
  (* case ty_sbsm *)
  + intros G t T U Ty IHTy St IHSt G1 G2 x Eq Bi Ok. subst.
    apply ty_sbsm with (subst_typ x y T).
    - apply* IHTy.
    - apply* IHSt.
  (* case ty_typ *)
  + intros. simpl. apply ty_typ.
  (* case ty_fld *)
  + intros. apply* ty_fld.
  (* case ty_mtd *)
  + intros L G T U t Ty IH G1 G2 x Eq Bi Ok. subst.
    apply_fresh ty_mtd as z. fold subst_trm. fold subst_typ.
    lets C: (@subst_open_commute_trm x y z t).
    unfolds open_trm. unfold subst_fvar in C. case_var.
    rewrite <- C.
    rewrite <- concat_assoc.
    assert (zL: z \notin L) by auto.
    specialize (IH z zL G1 (G2 & z ~ T) x). rewrite concat_assoc in IH.
    specialize (IH eq_refl Bi).
    unfold subst_ctx in IH. rewrite map_push in IH. unfold subst_ctx.
    apply IH. auto.
  (* case ty_dsnil *)
  + intros. apply ty_dsnil.
  (* case ty_dscons *)
  + intros. apply* ty_dscons.
Qed.

Print Assumptions subst_principles.

Lemma trm_subst_principle: forall G x y t S T,
  ok (G & x ~ S) ->
  ty_trm (G & x ~ S) t T ->
  ty_trm G (trm_var (avar_f y)) S ->
  ty_trm G (subst_trm x y t) (subst_typ x y T).
Proof.
  introv Hok tTy yTy. destruct (subst_principles y S) as [_ [_ [_ [_ [_ [P _]]]]]].
  specialize (P _ t T tTy G empty x).
  unfold subst_ctx in P. rewrite map_empty in P.
  repeat (progress (rewrite concat_empty_r in P)).
  apply* P.
Qed.

Lemma subdecs_subst_principle: forall G x y S Ds1 Ds2,
  ok (G & x ~ S) ->
  subdecs (G & x ~ S) Ds1 Ds2 ->
  ty_trm G (trm_var (avar_f y)) S ->
  subdecs G (subst_decs x y Ds1) (subst_decs x y Ds2).
Proof.
  introv Hok Sds yTy. destruct (subst_principles y S) as [_ [_ [_ [_ [P _]]]]].
  specialize (P _ Ds1 Ds2 Sds G empty x).
  unfold subst_ctx in P. rewrite map_empty in P.
  repeat (progress (rewrite concat_empty_r in P)).
  apply* P.
Qed.


(* ###################################################################### *)
(** ** Narrowing *)

Lemma subst_trm_undo: forall x y t, (subst_trm y x (subst_trm x y t)) = t.
Admitted.

Lemma subst_typ_undo: forall x y T, (subst_typ y x (subst_typ x y T)) = T.
Admitted.

Lemma narrow_ty_trm: forall G y T1 T2 u U,
  ok (G & y ~ T2) ->
  subtyp G T1 T2 ->
  ty_trm (G & y ~ T2) u U ->
  ty_trm (G & y ~ T1) u U.
Proof.
  introv Ok St Tyu.
  (* Step 1: rename *)
  pick_fresh z.
  assert (Okzy: ok (G & z ~ T2 & y ~ T2)) by admit.
  apply (weaken_ty_trm_middle Okzy) in Tyu.
  assert (Biz: binds z T2 (G & z ~ T2)) by auto.
  lets Tyz: (ty_var Biz).
  lets Tyu': (trm_subst_principle Okzy Tyu Tyz).
  (* Step 2: the actual substitution *)
  assert (Biy: binds y T1 (G & y ~ T1)) by auto.
  assert (Ok': ok (G & y ~ T1)) by admit.
  apply (weaken_subtyp_end Ok') in St.
  lets Tyy: (ty_sbsm (ty_var Biy) St).
  assert (Okyz: ok (G & y ~ T1 & z ~ T2)) by auto.
  apply (weaken_ty_trm_middle Okyz) in Tyu'.
  lets Tyu'': (trm_subst_principle Okyz Tyu' Tyy).
  rewrite subst_trm_undo, subst_typ_undo in Tyu''.
  exact Tyu''.
Qed.


(* ###################################################################### *)
(** ** More inversion lemmas *)

Lemma invert_var_has_dec: forall G x l D,
  has G (trm_var (avar_f x)) l D ->
  exists T Ds D', ty_trm G (trm_var (avar_f x)) T /\
                  exp G T Ds /\
                  decs_has Ds l D' /\
                  open_dec x D' = D.
Proof.
  introv Has. inversions Has.
  (* case has_trm *)
  + subst. exists T Ds D. auto.
  (* case has_var *)
  + exists T Ds D0. auto.
Qed.

Lemma invert_has: forall G t l D,
   has G t l D ->
   (exists T Ds,      ty_trm G t T /\
                      exp G T Ds /\
                      decs_has Ds l D /\
                      (forall z : var, open_dec z D = D))
\/ (exists x T Ds D', t = (trm_var (avar_f x)) /\
                      ty_trm G (trm_var (avar_f x)) T /\
                      exp G T Ds /\
                      decs_has Ds l D' /\
                      open_dec x D' = D).
Proof.
  introv Has. inversions Has.
  (* case has_trm *)
  + subst. left. exists T Ds. auto.
  (* case has_var *)
  + right. exists v T Ds D0. auto.
Qed.

Lemma invert_var_has_fld: forall G x l T,
  has G (trm_var (avar_f x)) l (dec_fld T) ->
  exists X Ds T', ty_trm G (trm_var (avar_f x)) X /\
                  exp G X Ds /\
                  decs_has Ds l (dec_fld T') /\
                  open_typ x T' = T.
Proof.
  introv Has. apply invert_var_has_dec in Has.
  destruct Has as [X [Ds [D [Tyx [Exp [Has Eq]]]]]].
  destruct D as [ Lo Hi | T' | T1 T2 ]; try solve [ inversion Eq ].
  unfold open_dec, open_rec_dec in Eq. fold open_rec_typ in Eq.
  inversion Eq as [Eq'].
  exists X Ds T'. auto.
Qed.

Lemma invert_var_has_mtd: forall G x l S U,
  has G (trm_var (avar_f x)) l (dec_mtd S U) ->
  exists X Ds S' U', ty_trm G (trm_var (avar_f x)) X /\
                     exp G X Ds /\
                     decs_has Ds l (dec_mtd S' U') /\
                     open_typ x S' = S /\
                     open_typ x U' = U.
Proof.
  introv Has. apply invert_var_has_dec in Has.
  destruct Has as [X [Ds [D [Tyx [Exp [Has Eq]]]]]].
  destruct D as [ Lo Hi | T' | S' U' ]; try solve [ inversion Eq ].
  unfold open_dec, open_rec_dec in Eq. fold open_rec_typ in Eq.
  inversion Eq as [Eq'].
  exists X Ds S' U'. auto.
Qed.

Lemma subtyp_refl_all: forall G T, subtyp G T T.
Admitted.

Lemma invert_ty_var: forall G x T,
  ty_trm G (trm_var (avar_f x)) T ->
  exists T', subtyp G T' T /\ binds x T' G.
Proof.
  introv Ty. gen_eq t: (trm_var (avar_f x)). gen x.
  induction Ty; intros x' Eq; try (solve [ discriminate ]).
  + inversions Eq. exists T. apply (conj (subtyp_refl_all _ _)). auto.
  + subst. specialize (IHTy _ eq_refl). destruct IHTy as [T' [St Bi]].
    exists T'. split.
    - apply subtyp_trans with T; assumption.
    - exact Bi.
Qed.

Lemma invert_ty_sel_var: forall G x l T,
  ty_trm G (trm_sel (trm_var (avar_f x)) l) T ->
  has G (trm_var (avar_f x)) (label_fld l) (dec_fld T).
Proof.
  introv Ty. gen_eq t0: (trm_sel (trm_var (avar_f x)) l). gen x l.
  induction Ty; try (solve [ intros; discriminate ]).
  (* base case: no subsumption *)
  + intros x l0 Eq. inversions Eq. assumption.
  (* step: subsumption *)
  + intros x l Eq. subst. specialize (IHTy _ _ eq_refl).
    apply invert_var_has_fld in IHTy.
    destruct IHTy as [X [Ds [T' [Tyx [Exp [Has Eq]]]]]].
    (*
    assert Tyx': ty_trm G (trm_var (avar_f x)) (ty_or X (typ_bind (dec_fld U)))
      by subsumption
    then the expansion of (ty_or X (typ_bind (dec_fld U))) has (dec_fld (t_or T U))
    since T <: U, (t_or T U) is kind of the same as U <-- but not enough!
    *)
Abort.

Lemma exp_to_subtyp: forall G T Ds,
  exp G T Ds ->
  subtyp G T (typ_bind Ds).
Admitted.

Lemma invert_ty_sel: forall G t l T,
  ty_trm G (trm_sel t l) T ->
  has G t (label_fld l) (dec_fld T).
Proof.
  introv Ty. gen_eq t0: (trm_sel t l). gen t l.
  induction Ty; intros t' l' Eq; try (solve [ discriminate ]).
  + inversions Eq. assumption.
  + subst. rename t' into t, l' into l. specialize (IHTy _ _ eq_refl).
    apply invert_has in IHTy.
    destruct IHTy as [IHTy | IHTy].
    (* case has_trm *)
    - destruct IHTy as [X [Ds [Tyt [Exp [DsHas CloT]]]]].
      (* U occurs in a subtype judgment, so it's closed: *)
      assert (CloU: forall z, open_typ z U = U) by admit.
      lets St1: (exp_to_subtyp Exp).
      assert (St2: subtyp G (typ_bind Ds) (typ_bind (decs_cons l (dec_fld U) decs_nil))). {
        apply_fresh subtyp_bind as z.
        apply subdecs_push with (dec_fld T); fold open_rec_typ; simpl.
        * rewrite <- (CloT z). apply (decs_has_open z DsHas).
        * unfold open_dec, open_rec_dec. fold open_rec_typ. apply subdec_fld.
          rewrite -> CloU. refine (weaken_subtyp_end _ H). admit.
        * apply subdecs_empty.
      }
      apply has_trm with (typ_bind (decs_cons l (dec_fld U) decs_nil))
                                   (decs_cons l (dec_fld U) decs_nil).
      * refine (ty_sbsm _ St2). apply (ty_sbsm Tyt St1).
      * apply exp_bind.
      * unfold decs_has, get_dec. simpl. case_if. reflexivity.
      * intro z. specialize (CloU z). unfold open_dec, open_rec_dec. 
        fold open_rec_typ. f_equal. apply CloU.
    (* case has_var *)
    - admit. (* probably similar *)
Qed.

Lemma invert_ty_sel_old: forall G t l T,
  ty_trm G (trm_sel t l) T ->
  exists T', subtyp G T' T /\ has G t (label_fld l) (dec_fld T').
Proof.
  introv Ty. gen_eq t0: (trm_sel t l). gen t l.
  induction Ty; intros t' l' Eq; try (solve [ discriminate ]).
  + inversions Eq. exists T. apply (conj (subtyp_refl_all _ _)). auto.
  + subst. rename t' into t, l' into l. specialize (IHTy _ _ eq_refl).
    destruct IHTy as [T' [St Has]]. exists T'. split.
    - apply subtyp_trans with T; assumption.
    - exact Has.
Qed.

Lemma invert_ty_call: forall G t m V u,
  ty_trm G (trm_call t m u) V ->
  exists U, has G t (label_mtd m) (dec_mtd U V) /\ ty_trm G u U.
Proof.
  introv Ty. gen_eq e: (trm_call t m u). gen t m u.
  induction Ty; intros t0 m0 u0 Eq; try solve [ discriminate ]; symmetry in Eq.
  + (* case ty_call *)
    inversions Eq. exists U. auto.
  + (* case ty_sbsm *)
    subst t. specialize (IHTy _ _ _ eq_refl).
    (* need to turn (dec_mtd U0 T) into (dec_mtd U0 U) using T <: U, but there's
       no subsumption in has, so we would need to do the subsumption when
       typing t0 --> tricky *)
Abort.

Lemma invert_ty_call: forall G t m V u,
  ty_trm G (trm_call t m u) V ->
  exists U, has G t (label_mtd m) (dec_mtd U V) /\ ty_trm G u U.
Proof.
  intros. inversions H.
  + eauto.
  + admit. (* subsumption case *)
Qed. (* TODO we don't want to depend on this! *)


Lemma invert_ty_new: forall G ds Ds T2,
  ty_trm G (trm_new Ds ds) T2 ->
  subtyp G (typ_bind Ds) T2 /\
  exists L, (forall x, x \notin L ->
               ty_defs (G & x ~ typ_bind Ds) (open_defs x ds) (open_decs x Ds)) /\
            (forall x, x \notin L ->
               forall M S U, decs_has (open_decs x Ds) M (dec_typ S U) ->
                             subtyp (G & x ~ typ_bind Ds) S U).
Proof.
  introv Ty. gen_eq t0: (trm_new Ds ds). gen Ds ds.
  induction Ty; intros Ds' ds' Eq; try (solve [ discriminate ]); symmetry in Eq.
  + (* case ty_new *)
    inversions Eq. apply (conj (subtyp_refl_all _ _)).
    exists L. auto.
  + (* case ty_sbsm *)
    subst. rename Ds' into Ds, ds' into ds. specialize (IHTy _ _ eq_refl).
    destruct IHTy as [St IHTy].
    apply (conj (subtyp_trans St H) IHTy).
Qed.

Lemma subdecs_trans: forall G z Ds1 Ds2 Ds3,
  subdecs (G & z ~ typ_bind Ds1) (open_decs z Ds1) (open_decs z Ds2) ->
  subdecs (G & z ~ typ_bind Ds2) (open_decs z Ds2) (open_decs z Ds3) ->
  subdecs (G & z ~ typ_bind Ds1) (open_decs z Ds1) (open_decs z Ds3).
Admitted.

(* TODO define imode *)
Lemma inv_pushback: forall G T1 T2,
  subtyp G T1 T2 ->
  forall T2', T2' = T2 -> subtyp G T1 T2' (* subtyp without inv *).
Proof.
  apply (subtyp_ind (fun G T1 T2 => forall T2', T2' = T2 -> subtyp G T1 T2')).
  + (* case subtyp_refl *)
    admit.
  + (* case subtyp_top *)
    admit.
  + (* case subtyp_bot *)
    admit.
  + (* case subtyp_bind *)
    admit.
  + (* case subtyp_sel_l *)
    admit.
  + (* case subtyp_sel_r *)
    admit.
  + (* case subtyp_trans *)
    admit.
  + (* case subtyp_inv_typ_lo *)
    introv St IH Exp1 Exp2 DsHas1 DsHas2.
    (* to show: Lo2 <: Lo1 without using inversion axiom at top level *)
    assert (subtyp G Lo2 Lo1).
    clear IH.
    (* real IH is: [T1 <: T2] has no inversion at top level *)
    

  + (* case subtyp_inv_typ_hi *)
    admit.
  + (* case subtyp_inv_fld *)
    admit.
  + (* case subtyp_inv_mtd_arg *)
    admit.
  + (* case subtyp_inv_mtd_ret *)
    admit.

Qed.


(* Key lemma of the whole proof: How to prove it??? *)
Lemma invert_subtyp_bind: forall G Ds1 Ds2,
  subtyp G (typ_bind Ds1) (typ_bind Ds2) ->
  exists L, forall z : var, z \notin L ->
    subdecs (G & z ~ typ_bind Ds1) (open_decs z Ds1) (open_decs z Ds2).
Proof.
  introv St. gen_eq T2: (typ_bind Ds2). gen_eq T1: (typ_bind Ds1).
  gen G T1 T2 St Ds1 Ds2.
  (* We don't use the [induction] tactic because we want to intro everything ourselves: *)
  apply (subtyp_ind (fun G T1 T2 => forall Ds1 Ds2,
    T1 = typ_bind Ds1 ->
    T2 = typ_bind Ds2 ->
    exists L, forall z : var, z \notin L ->
              subdecs (G & z ~ T1) (open_decs z Ds1) (open_decs z Ds2)));
  try (intros; subst; discriminate).
  (* case subtyp_bind *)
  + intros L G Ds1' Ds2' Sds Ds1 Ds2 Eq1 Eq2. inversions Eq1; inversions Eq2.
    exists L. assumption.
  (* case subtyp_trans: *)
  + intros G T1 T2 T3 St12 IH12 St23 IH23 Ds1 Ds3 Eq1 Eq3. subst T1 T3.
    (* inversion St12; inversion St23; subst; try discriminate. *)
    destruct T2 as [ | | Ds2 | p M ].
    - admit. (* St23 is a contradiction *)
    - admit. (* St12 is a contradiction *)
    - specialize (IH12 _ _ eq_refl eq_refl). destruct IH12 as [L12 IH12].
      specialize (IH23 _ _ eq_refl eq_refl). destruct IH23 as [L23 IH23].
      exists (L12 \u L23).
      intros z zL123.
      assert (zL12: z \notin L12) by auto. specialize (IH12 z zL12).
      assert (zL23: z \notin L23) by auto. specialize (IH23 z zL23).
      apply (subdecs_trans _ IH12 IH23).
    - (* The famous case with p.L in the middle !!
         Need stronger IH, maybe something with expansions instead of typ_bind? *)
      admit.
  + (* case subtyp_inv_typ_lo *)
    introv St12 IH12 Exp1 Exp2 Ds1Has Ds2Has. intros DsLo2 DsLo1 Eq1 Eq2. subst.
    admit.
  + (* case subtyp_inv_typ_hi *)
    admit.
  + (* case subtyp_inv_fld *)
    admit.
  + (* case subtyp_inv_mtd_arg *)
    admit.
  + (* case subtyp_inv_mtd_ret *)
    admit.
Abort.

Lemma invert_subtyp_bind: forall G Ds1 Ds2,
  subtyp G (typ_bind Ds1) (typ_bind Ds2) ->
  exists L, forall z : var, z \notin L ->
    subdecs (G & z ~ typ_bind Ds1) (open_decs z Ds1) (open_decs z Ds2).
Proof.
  introv St. inversions St.
  (* case subtyp_bind *)
  + exists L. assumption.
  (* case subtyp_trans: ??? *)
  + admit.
  (* inversion cases: ??? *)
  + inversions H. 
Admitted. (* <- !!! *)

Lemma invert_wf_sto_with_weakening: forall s G,
  wf_sto s G ->
  forall x ds Ds T,
    binds x (object Ds ds) s -> 
    binds x T G 
    -> T = (typ_bind Ds) 
    /\ ty_defs G (open_defs x ds) (open_decs x Ds)
    /\ (forall L S U, decs_has (open_decs x Ds) L (dec_typ S U) -> subtyp G S U).
Proof.
  introv Wf Bs BG.
  lets P: (invert_wf_sto Wf).
  specialize (P x ds Ds T Bs BG).
  destruct P as [EqT [G1 [G2 [EqG [Ty F]]]]]. subst.
  apply (conj eq_refl).
  lets Ok: (wf_sto_to_ok_G Wf).
  split.
  + apply (weaken_ty_defs_end Ok Ty).
  + intros L S U Has. specialize (F L S U Has). apply (weaken_subtyp_end Ok F).
Qed.

Lemma invert_wf_sto_with_sbsm: forall s G,
  wf_sto s G ->
  forall x ds Ds T, 
    binds x (object Ds ds) s ->
    ty_trm G (trm_var (avar_f x)) T (* <- instead of binds *)
    -> subtyp G (typ_bind Ds) T
    /\ ty_defs G (open_defs x ds) (open_decs x Ds)
    /\ (forall L S U, decs_has (open_decs x Ds) L (dec_typ S U) -> subtyp G S U).
Proof.
  introv Wf Bis Tyx.
  apply invert_ty_var in Tyx. destruct Tyx as [T'' [St BiG]].
  destruct (invert_wf_sto_with_weakening Wf Bis BiG) as [EqT [Tyds F]].
  subst T''.
  lets Ok: (wf_sto_to_ok_G Wf).
  apply (conj St).
  auto.
Qed.


(* ###################################################################### *)
(** Soundness helper lemmas *)

Lemma decs_has_preserves_sub: forall G Ds1 Ds2 l D2,
  decs_has Ds2 l D2 ->
  subdecs G Ds1 Ds2 ->
  exists D1, decs_has Ds1 l D1 /\ subdec G D1 D2.
Proof.
  introv Has Sds. induction Ds2.
  + inversion Has.
  + unfold decs_has, get_dec in Has. inversions Sds. case_if.
    - inversions Has. exists D1. auto.
    - fold get_dec in Has. apply* IHDs2.
Qed.

(*
Lemma ty_def_sbsm: forall G d D1 D2,
  ok G ->
  ty_def G d D1 ->
  subdec G D1 D2 ->
  ty_def G d D2.
Proof.
  introv Ok Ty Sd. destruct Ty; inversion Sd; try discriminate; subst; clear Sd.
  + apply ty_typ.
  + apply (ty_fld (ty_sbsm H H2)).
  + apply ty_mtd with (L \u dom G).
    intros x Fr. assert (xL: x \notin L) by auto. specialize (H x xL).
    assert (Okx: ok (G & x ~ S2)) by auto.
    apply (weaken_subtyp_end Okx) in H5.
    refine (ty_sbsm _ H5).
    refine (narrow_ty_trm _ H3 H).
    auto.
Qed.

Lemma ty_defs_sbsm: forall L G ds Ds1 Ds2,
  ok G ->
  ty_defs G ds Ds1 ->
  (forall x, x \notin L -> 
     subdecs (G & x ~ typ_bind Ds1) (open_decs x Ds1) (open_decs x Ds2)) ->
  ty_defs G ds Ds2.
Admitted.
*)

(*
Lemma subtyp_has_same: forall
  typ_trm G t T1 ->
  typ_trm G t T2 ->
  subtyp G T1 T2 ->
  has G t l D ->
  has G t l 
  

  exp G T2 Ds ->
  subtyp G T1 T2 ->
  exp G T1 Ds.


Lemma subtyp_expands_same: forall G T1 T2 Ds,
  exp G T2 Ds ->
  subtyp G T1 T2 ->
  exp G T1 Ds.
Proof.
  introv Exp. gen T1. induction Exp; introv St.
  (* case exp_top *)
  + destruct T1.
    (* case T1 = typ_top *)
    - apply exp_top.
    (* case T1 = typ_bot *)
    -z inversions St.

Qed.

Lemma exp_preserves_sub: forall G T1 T2 s Ds1 Ds2,
  subtyp G T1 T2 ->
  wf_sto s G ->
  exp G T1 Ds1 ->
  exp G T2 Ds2 ->
  exists L, forall z : var, z \notin L ->
    subdecs (G & z ~ typ_bind Ds1) (open_decs z Ds1) (open_decs z Ds2).
Proof.
Abort. (* does not hold with imprecise expansion *)

Lemma exp_preserves_sub: forall G Ds1 T2 s Ds2,
  subtyp G (typ_bind Ds1) T2 ->
  wf_sto s G ->
  exp G T2 Ds2 ->
  exists L, forall z : var, z \notin L ->
    subdecs (G & z ~ typ_bind Ds1) (open_decs z Ds1) (open_decs z Ds2).
Proof.
  introv St. gen_eq T1: (typ_bind Ds1). gen s Ds1 Ds2.
  induction St; introv Eq Wf Exp2; try discriminate; lets Ok: (wf_sto_to_ok_G Wf).
  + (* case subtyp_top *)
    subst. inversions Exp2. exists vars_empty. intros.
    unfold open_decs, open_rec_decs. apply subdecs_empty.
  + (* case subtyp_bind *)
    inversions Eq. inversions Exp2. exists L. exact H.
  + (* case subtyp_sel_r *)
    subst.
    lets St1: (subtyp_sel_r H).
    admit. (*???*)
  + (* case subtyp_trans *)
    rename Ds2 into Ds3. rename Exp2 into Exp3.
Abort.
*)
(*
Lemma precise_decs_subdecs_of_imprecise_decs: forall s G x ds X2 Ds1 Ds2, 
  wf_sto s G ->
  binds x (object Ds1 ds) s ->
  ty_trm G (trm_var (avar_f x)) X2 ->
  exp G X2 Ds2 ->
  subdecs G (open_decs x Ds1) (open_decs x Ds2).
Proof.
  introv Wf Bis Tyx Exp2.
  lets Ok: (wf_sto_to_ok_G Wf).
  destruct (invert_wf_sto_with_sbsm Wf Bis Tyx) as [St _]. 
     (* invert_wf_sto_with_sbsm should return hyp. of subtyp_bind! *)
  lets Sds: (exp_preserves_sub St Wf Exp1 Exp2).
  destruct Sds as [L Sds].
  pick_fresh z. assert (zL: z \notin L) by auto. specialize (Sds z zL).
  lets BiG: (sto_binds_to_ctx_binds Wf Bis).
  assert (Sds': subdecs oktrans (G & z ~ X1) (open_decs z Ds1) (open_decs z Ds2))
    by admit. (* narrowing to type X1 (which expands) *)
  assert (Ok': ok (G & z ~ X1)) by auto.
  lets P: (@subdecs_subst_principle oktrans _ z x X1 
              (open_decs z Ds1) (open_decs z Ds2) Ok' Sds' BiG).
  assert (zDs1: z \notin fv_decs Ds1) by auto.
  assert (zDs2: z \notin fv_decs Ds2) by auto.
  rewrite <- (@subst_intro_decs z x Ds1 zDs1) in P.
  rewrite <- (@subst_intro_decs z x Ds2 zDs2) in P.
  exact P.
Qed.
*)


Lemma has_sound: forall s G x Ds1 ds l D2,
  wf_sto s G ->
  binds x (object Ds1 ds) s ->
  has G (trm_var (avar_f x)) l D2 ->
  exists D1,
    ty_defs G (open_defs x ds) (open_decs x Ds1) /\
    decs_has (open_decs x Ds1) l D1 /\
    subdec G D1 D2.
Proof.
  introv Wf Bis Has.
  apply invert_var_has_dec in Has.
  destruct Has as [X2 [Ds2 [T [Tyx [Exp2 [Ds2Has Eq]]]]]]. subst.
  destruct (invert_wf_sto_with_sbsm Wf Bis Tyx) as [St [Tyds _]].
  lets St': (exp_to_subtyp Exp2).
  lets Sds: (invert_subtyp_bind (subtyp_trans St St')).
  destruct Sds as [L Sds].
  pick_fresh z. assert (zL: z \notin L) by auto. specialize (Sds z zL).
  lets BiG: (sto_binds_to_ctx_binds Wf Bis).
  lets Tyx1: (ty_var BiG).
  lets Ok: (wf_sto_to_ok_G Wf).
  assert (Ok': ok (G & z ~ typ_bind Ds1)) by auto.
  lets Sds': (@subdecs_subst_principle _ z x (typ_bind Ds1)
              (open_decs z Ds1) (open_decs z Ds2) Ok' Sds Tyx1).
  assert (zDs1: z \notin fv_decs Ds1) by auto.
  assert (zDs2: z \notin fv_decs Ds2) by auto.
  rewrite <- (@subst_intro_decs z x Ds1 zDs1) in Sds'.
  rewrite <- (@subst_intro_decs z x Ds2 zDs2) in Sds'.
  apply (decs_has_open x) in Ds2Has.
  (* apply (subdecs_to_subdecs_alt Wf) in Sds'. *)
  destruct (decs_has_preserves_sub Ds2Has Sds') as [D1 [Ds1Has Sd]].
  exists D1.
  apply (conj Tyds (conj Ds1Has Sd)).
Qed.


(* ###################################################################### *)
(** ** Progress *)

Theorem progress_result: progress.
Proof.
  introv Wf Ty. gen G e T Ty s Wf.
  set (progress_for := fun s e =>
                         (exists e' s', red e s e' s') \/
                         (exists x o, e = (trm_var (avar_f x)) /\ binds x o s)).
  apply (ty_has_mutind
    (fun G e l d (Hhas: has G e l d)  => forall s, wf_sto s G -> progress_for s e)
    (fun G e T   (Hty:  ty_trm G e T) => forall s, wf_sto s G -> progress_for s e));
    unfold progress_for; clear progress_for.
  (* case has_trm *)
  + intros. auto.
  (* case has_var *)
  + intros G v T Ds l D Ty IH Exp Has s Wf.
    right. apply invert_ty_var in Ty. destruct Ty as [T' [St BiG]].
    destruct (ctx_binds_to_sto_binds Wf BiG) as [o Bis].
    exists v o. auto.
  (* case ty_var *)
  + intros G x T BiG s Wf.
    right. destruct (ctx_binds_to_sto_binds Wf BiG) as [o Bis].
    exists x o. auto.
  (* case ty_sel *)
  + intros G t l T Has IH s Wf.
    left. specialize (IH s Wf). destruct IH as [IH | IH].
    (* receiver is an expression *)
    - destruct IH as [s' [e' IH]]. do 2 eexists. apply (red_sel1 l IH).
    (* receiver is a var *)
    - destruct IH as [x [[Ds1 ds] [Eq Bis]]]. subst.
      lets P: (has_sound Wf Bis Has).
      destruct P as [D1 [Tyds [Ds1Has Sd]]].
      destruct (decs_has_to_defs_has Tyds Ds1Has) as [d dsHas].
      destruct (defs_has_fld_sync dsHas) as [r Eqd]. subst.
      exists (trm_var r) s.
      apply (red_sel Bis dsHas).
  (* case ty_call *)
  + intros G t m U V u Has IHrec Tyu IHarg s Wf. left.
    specialize (IHrec s Wf). destruct IHrec as [IHrec | IHrec].
    - (* case receiver is an expression *)
      destruct IHrec as [s' [e' IHrec]]. do 2 eexists. apply (red_call1 m _ IHrec).
    - (* case receiver is  a var *)
      destruct IHrec as [x [[Ds ds] [Eq Bis]]]. subst.
      specialize (IHarg s Wf). destruct IHarg as [IHarg | IHarg].
      (* arg is an expression *)
      * destruct IHarg as [s' [e' IHarg]]. do 2 eexists. apply (red_call2 x m IHarg).
      (* arg is a var *)
      * destruct IHarg as [y [o [Eq Bisy]]]. subst.
        lets P: (has_sound Wf Bis Has).
        destruct P as [D [Tyds [DsHas Sd]]].
        destruct (decs_has_to_defs_has Tyds DsHas) as [d dsHas].
        destruct (defs_has_mtd_sync dsHas) as [body Eqd]. subst.
        exists (open_trm y body) s.
        apply (red_call y Bis dsHas).
  (* case ty_new *)
  + intros L G ds Ds Tyds F s Wf.
    left. pick_fresh x.
    exists (trm_var (avar_f x)) (s & x ~ (object Ds ds)).
    apply* red_new.
  (* case ty_sbsm *)
  + intros. auto_specialize. assumption.
Qed.

Print Assumptions progress_result.


Lemma ty_open_defs_change_var: forall x y G ds Ds S,
  ok (G & x ~ S) ->
  ok (G & y ~ S) ->
  x \notin fv_defs ds ->
  x \notin fv_decs Ds ->
  ty_defs (G & x ~ S) (open_defs x ds) (open_decs x Ds) ->
  ty_defs (G & y ~ S) (open_defs y ds) (open_decs y Ds).
Proof.
  introv Okx Oky Frds FrDs Ty.
  destruct (classicT (x = y)) as [Eq | Ne].
  + subst. assumption.
  + assert (Okyx: ok (G & y ~ S & x ~ S)) by destruct* (ok_push_inv Okx).
    assert (Ty': ty_defs (G & y ~ S & x ~ S) (open_defs x ds) (open_decs x Ds))
      by apply (weaken_ty_defs_middle Ty Okyx).
    rewrite* (@subst_intro_defs x y ds).
    rewrite* (@subst_intro_decs x y Ds).
    lets Tyy: (ty_var (binds_push_eq y S G)).
    destruct (subst_principles y S) as [_ [_ [_ [_ [_ [_ [_ P]]]]]]].
    specialize (P _ _ _ Ty' (G & y ~ S) empty x).
    rewrite concat_empty_r in P.
    specialize (P eq_refl Tyy Okyx).
    unfold subst_ctx in P. rewrite map_empty in P. rewrite concat_empty_r in P.
    exact P.
Qed.


(* ###################################################################### *)
(** ** Preservation *)

Theorem preservation_proof:
  forall e s e' s' (Hred: red e s e' s') G T (Hwf: wf_sto s G) (Hty: ty_trm G e T),
  (exists H, wf_sto s' (G & H) /\ ty_trm (G & H) e' T).
Proof.
  intros s e s' e' Red. induction Red.
  (* red_call *)
  + intros G U2 Wf TyCall. rename H into Bis, H0 into dsHas, T into Ds1.
    exists (@empty typ). rewrite concat_empty_r. apply (conj Wf).
    apply invert_ty_call in TyCall.
    destruct TyCall as [T2 [Has Tyy]].
    lets P: (has_sound Wf Bis Has).
    destruct P as [D1 [Tyds [Ds1Has Sd]]].
    subdec_sync_for Sd; try discriminate. symmetry in Eq2. inversions Eq2.
    inversions Sd. rename H3 into StT, H5 into StU.
    destruct (invert_ty_mtd_inside_ty_defs Tyds dsHas Ds1Has) as [L0 Tybody].
    apply invert_ty_var in Tyy.
    destruct Tyy as [T3 [StT3 Biy]].
    pick_fresh y'.
    rewrite* (@subst_intro_trm y' y body).
    assert (Fry': y' \notin fv_typ U2) by auto.
    assert (Eqsubst: (subst_typ y' y U2) = U2)
      by apply* subst_fresh_typ_dec_decs.
    rewrite <- Eqsubst.
    lets Ok: (wf_sto_to_ok_G Wf).
    apply (@trm_subst_principle G y' y (open_trm y' body) T1 _).
    - auto.
    - assert (y'L0: y' \notin L0) by auto. specialize (Tybody y' y'L0).
      apply (ty_sbsm Tybody).
      apply weaken_subtyp_end. auto. apply StU.
    - refine (ty_sbsm _ StT). refine (ty_sbsm _ StT3). apply (ty_var Biy).
  (* red_sel *)
  + intros G T3 Wf TySel. rename H into Bis, H0 into dsHas, T into Ds1.
    exists (@empty typ). rewrite concat_empty_r. apply (conj Wf).
    apply invert_ty_sel_old in TySel.
    destruct TySel as [T2 [StT23 Has]].
    lets P: (has_sound Wf Bis Has).
    destruct P as [D1 [Tyds [Ds1Has Sd]]].
    subdec_sync_for Sd; try discriminate. symmetry in Eq2. inversions Eq2.
    inversions Sd. rename H2 into StT12.
    refine (ty_sbsm _ StT23).
    refine (ty_sbsm _ StT12).
    apply (invert_ty_fld_inside_ty_defs Tyds dsHas Ds1Has).
  (* red_new *)
  + rename T into Ds1. intros G T2 Wf Ty.
    apply invert_ty_new in Ty.
    destruct Ty as [StT12 [L [Tyds F]]].
    exists (x ~ (typ_bind Ds1)).
    pick_fresh x'. assert (Frx': x' \notin L) by auto.
    specialize (Tyds x' Frx').
    specialize (F x' Frx').
    assert (xG: x # G) by apply* sto_unbound_to_ctx_unbound.
    split.
    - apply (wf_sto_push _ Wf H xG).
      * apply* (@ty_open_defs_change_var x').
      * intros M S U dsHas. specialize (F M S U). admit. (* meh TODO *)
    - lets Ok: (wf_sto_to_ok_G Wf). assert (Okx: ok (G & x ~ (typ_bind Ds1))) by auto.
      apply (weaken_subtyp_end Okx) in StT12.
      refine (ty_sbsm _ StT12). apply ty_var. apply binds_push_eq.
  (* red_call1 *)
  + intros G Tr Wf Ty.
    apply invert_ty_call in Ty.
    destruct Ty as [Ta [Has Tya]].
    apply invert_has in Has.
    destruct Has as [Has | Has].
    - (* case has_trm *)
      destruct Has as [To [Ds [Tyo [Exp [DsHas Clo]]]]].
      specialize (IHRed G To Wf Tyo). destruct IHRed as [H [Wf' Tyo']].
      lets Ok: (wf_sto_to_ok_G Wf').
      exists H. apply (conj Wf'). apply (@ty_call (G & H) o' m Ta Tr a).
      * refine (has_trm Tyo' _ DsHas Clo).
        apply (weaken_exp_end Ok Exp).
      * apply (weaken_ty_trm_end Ok Tya).
    - (* case has_var *)
      destruct Has as [x [Tx [Ds [D' [Eqx _]]]]]. subst.
      inversion Red. (* contradiction: vars don't step *)
  (* red_call2 *)
  + intros G Tr Wf Ty.
    apply invert_ty_call in Ty.
    destruct Ty as [Ta [Has Tya]].
    specialize (IHRed G Ta Wf Tya).
    destruct IHRed as [H [Wf' Tya']].
    exists H. apply (conj Wf'). apply (@ty_call (G & H) _ m Ta Tr a').
    - lets Ok: wf_sto_to_ok_G Wf'.
      apply (weaken_has_end Ok Has).
    - assumption.
  (* red_sel1 *)
  + intros G T2 Wf TySel.
    apply invert_ty_sel in TySel.
    rename TySel into Has.
    apply invert_has in Has.
    destruct Has as [Has | Has].
    - (* case has_trm *)
      destruct Has as [To [Ds [Tyo [Exp [DsHas Clo]]]]].
      specialize (IHRed G To Wf Tyo). destruct IHRed as [H [Wf' Tyo']].
      lets Ok: (wf_sto_to_ok_G Wf').
      exists H. apply (conj Wf').
      apply (@ty_sel (G & H) o' l T2).
      refine (has_trm Tyo' _ DsHas Clo).
      apply (weaken_exp_end Ok Exp).
    - (* case has_var *)
      destruct Has as [x [Tx [Ds [D' [Eqx _]]]]]. subst.
      inversion Red. (* contradiction: vars don't step *)
Qed.

Theorem preservation_result: preservation.
Proof.
  introv Hwf Hty Hred.
  destruct (preservation_proof Hred Hwf Hty) as [H [Hwf' Hty']].
  exists (G & H). split; assumption.
Qed.

Print Assumptions preservation_result.

