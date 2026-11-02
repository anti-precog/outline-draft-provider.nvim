;; Sekcje (kontenery nadrzędne)
(section
  (title) @name) @definition.section

;; Grupy (kontenery) - opcjonalnie z nagłówkiem
(group
  (header)? @name) @definition.group

;; Elementy treści i znaczniki (widoczne jako liście w drzewie)
(narration) @name @definition.narration
(quotation) @name @definition.quotation
(dialog) @name @definition.dialog
(comment) @name @definition.comment
(header) @name @definition.header
(footer) @name @definition.footer
