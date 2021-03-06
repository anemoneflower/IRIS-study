From iris.proofmode Require Import tactics.
From iris.program_logic Require Export weakestpre.
From iris_examples.logrel.F_mu_ref Require Export rules typing.
From iris.algebra Require Import list.
Import uPred.

Definition logN : namespace := nroot .@ "logN".

(** interp : is a unary logical relation. *)
Section logrel.
  Context `{heapG Σ}.
  Notation D := (valO -n> iPropO Σ).
  Implicit Types τi : D.
  Implicit Types Δ : listO D.
  Implicit Types interp : listO D → D.

  Program Definition ctx_lookup (x : var) : listO D -n> D := λne Δ,
    from_option id (cconst True)%I (Δ !! x).
  Solve Obligations with solve_proper.

  Definition interp_unit : listO D -n> D := λne Δ w, ⌜w = UnitV⌝%I.

  Program Definition interp_prod
      (interp1 interp2 : listO D -n> D) : listO D -n> D := λne Δ w,
    (∃ w1 w2, ⌜w = PairV w1 w2⌝ ∧ interp1 Δ w1 ∧ interp2 Δ w2)%I.
  Solve Obligations with repeat intros ?; simpl; solve_proper.

  Program Definition interp_sum
      (interp1 interp2 : listO D -n> D) : listO D -n> D := λne Δ w,
    ((∃ w1, ⌜w = InjLV w1⌝ ∧ interp1 Δ w1) ∨ (∃ w2, ⌜w = InjRV w2⌝ ∧ interp2 Δ w2))%I.
  Solve Obligations with repeat intros ?; simpl; solve_proper.

  Program Definition interp_arrow
      (interp1 interp2 : listO D -n> D) : listO D -n> D := λne Δ w,
    (□ ∀ v, interp1 Δ v → WP App (# w) (# v) {{ interp2 Δ }})%I.
  Solve Obligations with repeat intros ?; simpl; solve_proper.

  Program Definition interp_forall
      (interp : listO D -n> D) : listO D -n> D := λne Δ w,
    (□ ∀ τi : D,
      ⌜(∀ v, Persistent (τi v))⌝ → WP TApp (# w) {{ interp (τi :: Δ) }})%I.
  Solve Obligations with repeat intros ?; simpl; solve_proper.

  Definition interp_rec1
      (interp : listO D -n> D) (Δ : listO D) (τi : D) : D := λne w,
    (□ (∃ v, ⌜w = FoldV v⌝ ∧ ▷ interp (τi :: Δ) v))%I.

  Global Instance interp_rec1_contractive
    (interp : listO D -n> D) (Δ : listO D) : Contractive (interp_rec1 interp Δ).
  Proof. by solve_contractive. Qed.


  Lemma fixpoint_interp_rec1_eq (interp : listO D -n> D) Δ x :
    fixpoint (interp_rec1 interp Δ) x ≡ interp_rec1 interp Δ (fixpoint (interp_rec1 interp Δ)) x.
  Proof. exact: (fixpoint_unfold (interp_rec1 interp Δ) x). Qed.

  Program Definition interp_rec (interp : listO D -n> D) : listO D -n> D := λne Δ,
    fixpoint (interp_rec1 interp Δ).
  Next Obligation.
    intros interp n Δ1 Δ2 HΔ; apply fixpoint_ne => τi w. solve_proper.
  Qed.

  Program Definition interp_ref_inv (l : loc) : D -n> iPropO Σ := λne τi,
    (∃ v, l ↦ v ∗ τi v)%I.
  Solve Obligations with solve_proper.

  Program Definition interp_ref
      (interp : listO D -n> D) : listO D -n> D := λne Δ w,
    (∃ l, ⌜w = LocV l⌝ ∧ inv (logN .@ l) (interp_ref_inv l (interp Δ)))%I.
  Solve Obligations with solve_proper.

  Fixpoint interp (τ : type) : listO D -n> D :=
    match τ return _ with
    | TUnit => interp_unit
    | TProd τ1 τ2 => interp_prod (interp τ1) (interp τ2)
    | TSum τ1 τ2 => interp_sum (interp τ1) (interp τ2)
    | TArrow τ1 τ2 => interp_arrow (interp τ1) (interp τ2)
    | TVar x => ctx_lookup x
    | TForall τ' => interp_forall (interp τ')
    | TRec τ' => interp_rec (interp τ')
    | Tref τ' => interp_ref (interp τ')
    end.
  Notation "⟦ τ ⟧" := (interp τ).

  Definition interp_env (Γ : list type)
      (Δ : listO D) (vs : list val) : iProp Σ :=
    (⌜length Γ = length vs⌝ ∗ [∗] zip_with (λ τ, ⟦ τ ⟧ Δ) Γ vs)%I.
  Notation "⟦ Γ ⟧*" := (interp_env Γ).

  Definition interp_expr (τ : type) (Δ : listO D) (e : expr) : iProp Σ :=
    WP e {{ ⟦ τ ⟧ Δ }}%I.

  Class env_Persistent Δ :=
    ctx_persistent : Forall (λ τi, ∀ v, Persistent (τi v)) Δ.
  Global Instance ctx_persistent_nil : env_Persistent [].
  Proof. by constructor. Qed.
  Global Instance ctx_persistent_cons τi Δ :
    (∀ v, Persistent (τi v)) → env_Persistent Δ → env_Persistent (τi :: Δ).
  Proof. by constructor. Qed.
  Global Instance ctx_persistent_lookup Δ x v :
    env_Persistent Δ → Persistent (ctx_lookup x Δ v).
  Proof. intros HΔ; revert x; induction HΔ=>-[|?] /=; apply _. Qed.
  Global Instance interp_persistent τ Δ v :
    env_Persistent Δ → Persistent (⟦ τ ⟧ Δ v).
  Proof.
    revert v Δ; induction τ=> v Δ HΔ; simpl; try apply _.
    rewrite /Persistent fixpoint_interp_rec1_eq /interp_rec1 /= intuitionistically_into_persistently.
    by apply persistently_intro'.
  Qed.
  Global Instance interp_env_base_persistent Δ Γ vs :
  env_Persistent Δ → TCForall Persistent (zip_with (λ τ, ⟦ τ ⟧ Δ) Γ vs).
  Proof.
    intros HΔ. revert vs.
    induction Γ => vs; simpl; destruct vs; constructor; apply _.
  Qed.
  Global Instance interp_env_persistent Γ Δ vs :
    env_Persistent Δ → Persistent (⟦ Γ ⟧* Δ vs) := _.

  Lemma interp_weaken Δ1 Π Δ2 τ :
    ⟦ τ.[upn (length Δ1) (ren (+ length Π))] ⟧ (Δ1 ++ Π ++ Δ2)
    ≡ ⟦ τ ⟧ (Δ1 ++ Δ2).
  Proof.
    revert Δ1 Π Δ2. induction τ=> Δ1 Π Δ2; simpl; auto.
    - intros w; simpl; properness; auto. by apply IHτ1. by apply IHτ2.
    - intros w; simpl; properness; auto. by apply IHτ1. by apply IHτ2.
    - intros w; simpl; properness; auto. by apply IHτ1. by apply IHτ2.
    - apply fixpoint_proper=> τi w /=.
      properness; auto. apply (IHτ (_ :: _)).
    - rewrite iter_up; destruct lt_dec as [Hl | Hl]; simpl.
      { by rewrite !lookup_app_l. }
      (* FIXME: Ideally we wouldn't have to do this kinf of surgery. *)
      change (bi_ofeO (uPredI (iResUR Σ))) with (uPredO (iResUR Σ)).
      rewrite !lookup_app_r; [|lia ..]. do 2 f_equiv. lia.
    - intros w; simpl; properness; auto. apply (IHτ (_ :: _)).
    - intros w; simpl; properness; auto. by apply IHτ.
  Qed.

  Lemma interp_subst_up Δ1 Δ2 τ τ' :
    ⟦ τ ⟧ (Δ1 ++ interp τ' Δ2 :: Δ2)
    ≡ ⟦ τ.[upn (length Δ1) (τ' .: ids)] ⟧ (Δ1 ++ Δ2).
  Proof.
    revert Δ1 Δ2; induction τ=> Δ1 Δ2; simpl.
    - done.
    - intros w; simpl; properness; auto. by apply IHτ1. by apply IHτ2.
    - intros w; simpl; properness; auto. by apply IHτ1. by apply IHτ2.
    - intros w; simpl; properness; auto. by apply IHτ1. by apply IHτ2.
    - apply fixpoint_proper=> τi w /=.
      properness; auto. apply (IHτ (_ :: _)).
    - rewrite iter_up; destruct lt_dec as [Hl | Hl]; simpl.
      { by rewrite !lookup_app_l. }
      (* FIXME: Ideally we wouldn't have to do this kinf of surgery. *)
      change (bi_ofeO (uPredI (iResUR Σ))) with (uPredO (iResUR Σ)).
      rewrite !lookup_app_r; [|lia ..].
      case EQ: (x - length Δ1) => [|n]; simpl.
      { symmetry. asimpl. apply (interp_weaken [] Δ1 Δ2 τ'). }
      change (bi_ofeO (uPredI (iResUR Σ))) with (uPredO (iResUR Σ)).
      rewrite !lookup_app_r; [|lia ..]. do 2 f_equiv. lia.
    - intros w; simpl; properness; auto. apply (IHτ (_ :: _)).
    - intros w; simpl; properness; auto. by apply IHτ.
  Qed.

  Lemma interp_subst Δ2 τ τ' v : ⟦ τ ⟧ (⟦ τ' ⟧ Δ2 :: Δ2) v ≡ ⟦ τ.[τ'/] ⟧ Δ2 v.
  Proof. apply (interp_subst_up []). Qed.

  Lemma interp_env_length Δ Γ vs : ⟦ Γ ⟧* Δ vs ⊢ ⌜length Γ = length vs⌝.
  Proof. by iIntros "[% ?]". Qed.

  Lemma interp_env_Some_l Δ Γ vs x τ :
    Γ !! x = Some τ → ⟦ Γ ⟧* Δ vs ⊢ ∃ v, ⌜vs !! x = Some v⌝ ∧ ⟦ τ ⟧ Δ v.
  Proof.
    iIntros (?) "[Hlen HΓ]"; iDestruct "Hlen" as %Hlen.
    destruct (lookup_lt_is_Some_2 vs x) as [v Hv].
    { by rewrite -Hlen; apply lookup_lt_Some with τ. }
    iExists v; iSplit. done. iApply (big_sepL_elem_of with "HΓ").
    apply elem_of_list_lookup_2 with x.
    rewrite lookup_zip_with; by simplify_option_eq.
  Qed.

  Lemma interp_env_nil Δ : (⟦ [] ⟧* Δ [])%I.
  Proof. iSplit; simpl; auto. Qed.
  Lemma interp_env_cons Δ Γ vs τ v :
    ⟦ τ :: Γ ⟧* Δ (v :: vs) ⊣⊢ ⟦ τ ⟧ Δ v ∗ ⟦ Γ ⟧* Δ vs.
  Proof.
    rewrite /interp_env /= (assoc _ (⟦ _ ⟧ _ _)) -(comm _ ⌜(_ = _)⌝%I) -assoc.
    by apply sep_proper; [apply pure_proper; lia|].
  Qed.

  Lemma interp_env_ren Δ (Γ : list type) (vs : list val) τi :
    ⟦ subst (ren (+1)) <$> Γ ⟧* (τi :: Δ) vs ⊣⊢ ⟦ Γ ⟧* Δ vs.
  Proof.
    apply sep_proper; [apply pure_proper; by rewrite fmap_length|].
    revert Δ vs τi; induction Γ=> Δ [|v vs] τi; csimpl; auto.
    apply sep_proper; auto. apply (interp_weaken [] [τi] Δ).
  Qed.
End logrel.

Typeclasses Opaque interp_env.
Notation "⟦ τ ⟧" := (interp τ).
Notation "⟦ τ ⟧ₑ" := (interp_expr τ).
Notation "⟦ Γ ⟧*" := (interp_env Γ).
