;; Sekcje
(section
  (title) @name) @definition.section

;; Grupy (łapiemy opcjonalnie header i footer wewnątrz grupy)
(group
  (header)? @definition.header
  (footer)? @definition.footer) @definition.group

;; Elementy treści
(narration) @definition.narration
(quotation) @definition.quotation
(dialog) @definition.dialog
(comment) @definition.comment
