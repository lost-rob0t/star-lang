% Durable StarLang project knowledge base.
% Consult this file (from anywhere) to load every focused KB module.
% Verified, reusable knowledge only; task state lives in .prolog/runs/.

:- prolog_load_context(directory, Dir),
   atomic_list_concat([Dir, '/toolchain'], Toolchain),
   atomic_list_concat([Dir, '/testing'], Testing),
   atomic_list_concat([Dir, '/compiler-ownership'], Ownership),
   atomic_list_concat([Dir, '/verification-workflow'], Workflow),
   consult(Toolchain),
   consult(Testing),
   consult(Ownership),
   consult(Workflow).
