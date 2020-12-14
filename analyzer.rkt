#lang racket/base

(require racket/match
         "ast.rkt"
         "baselib.rkt"
         "helper.rkt")

(provide analyze)

(define (type-compat? given expected)
  (match (cons given expected)
    [(cons t t) #t]
    [(cons '% t) #t]
    [(cons t '%) #t]
    [(cons (Ptr_t t1) (Ptr_t t2)) (type-compat? t1 t2)]
    [else #f]))

(define (expr-pos e)
  (match e
    [(Pnum _ p) p]
    [(Pstr _ p) p]
    [(Pvar _ p) p]
    [(Pcall _ _ p) p]))

(define (analyze-function f as pos env proc?)
  (unless (hash-has-key? env f)
    (err (format "unknown function '~a'" f) pos))
  (let ([ft (hash-ref env f)])
    (if proc?
        (unless (eq? 'void (Fun_t-ret ft))
          (err (format "functions must return void if used as instruction: '~a'" f) pos))
        (when (eq? 'void (Fun_t-ret ft))
          (err (format "void is not a valid expression type: '~a'" f) pos)))
    (unless (= (length (Fun_t-args ft)) (length as))
      (err (format "arity mismatch (expected ~a, given ~a)"
                   (length (Fun_t-args ft))
                   (length as))
           pos))
    (let ([aas (map (lambda (at a)
                      (let ([aa (analyze-expr a env)])
                        (if (type-compat? (cdr aa) at)
                            (car aa)
                            (errt at (cdr aa) (expr-pos a)))))
                    (Fun_t-args ft)
                    as)])
      (cons (Call f aas)
            (Fun_t-ret ft)))))

(define (analyze-expr expr env)
  (match expr
    [(Pnum v pos)
     (cons (Num v)
           'num)]
    [(Pstr v pos)
     (cons (Str v)
           'str)]
    [(Pvar n pos)
     (unless (hash-has-key? env n)
       (err (format "unbound variable: '~a'" n) pos))
     (cons (Var n)
           (hash-ref env n))]
    [(Pcall f as pos)
     (analyze-function f as pos env #f)]))

(define (analyze-instr instr env)
  (match instr
    [(Passign v e pos)
     (let ([ae (analyze-expr e env)])
       (cons (Assign v (car ae))
             (hash-set env v (cdr ae))))]
    [(Pcall f as pos)
     (cons (car (analyze-function f as pos env #t))
           env)]))

(define (analyze-prog prog env)
  (match prog
    [(list i)
     (list (car (analyze-instr i env)))]
    [(cons i p)
     (let ([ai (analyze-instr i env)])
       (cons (car ai)
             (analyze-prog p (cdr ai))))]))

(define (analyze ast)
  (analyze-prog ast *baselib-types*))