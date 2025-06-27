REPORT zautoprog_mmpv.

*----------------------------------------------------------------------*
*   Declaração de Dados
*----------------------------------------------------------------------*
DATA: lv_data_atual     TYPE d,
      lv_mes_atual      TYPE c LENGTH 2,
      lv_ano_atual      TYPE c LENGTH 4,
      lv_mes_seguinte   TYPE c LENGTH 2,
      lv_ano_seguinte   TYPE c LENGTH 4,
      lv_periodo_mmpv   TYPE mmpur_period, " Para o campo RMMZU-POPER
      lv_exercicio_mmpv TYPE gjahr.        " Para o campo RMMZU-POJAHR

DATA: lt_bdcdata TYPE TABLE OF bdcdata,
      ls_bdcdata TYPE bdcdata.

* Parâmetros de seleção (opcional, mas recomendado para flexibilidade)
PARAMETERS: p_bukrs TYPE bukrs DEFAULT '1000' OBLIGATORY, " Código da Empresa
              p_test  TYPE abap_bool DEFAULT abap_true.     " Modo de Teste (Verificar e diferir)

*----------------------------------------------------------------------*
*   Lógica Principal
*----------------------------------------------------------------------*
START-OF-SELECTION.

  *--------------------------------------------------------------------*
  *   1. Cálculo de Datas para MMPV
  *--------------------------------------------------------------------*
  lv_data_atual = sy-datum.
  lv_mes_atual = lv_data_atual+4(2).
  lv_ano_atual = lv_data_atual+0(4).

  IF lv_mes_atual = '12'.
    lv_mes_seguinte = '01'.
    lv_ano_seguinte = lv_ano_atual + 1.
  ELSE.
    lv_mes_seguinte = lv_mes_atual + 1.
    lv_ano_seguinte = lv_ano_atual.
    " Assegurar que o mês tem dois dígitos
    IF lv_mes_seguinte < 10 AND STRLEN( lv_mes_seguinte ) = 1.
      CONCATENATE '0' lv_mes_seguinte INTO lv_mes_seguinte.
    ENDIF.
  ENDIF.

  lv_periodo_mmpv = lv_mes_seguinte.
  lv_exercicio_mmpv = lv_ano_seguinte.

  WRITE: / 'Data Atual:', sy-datum DD/MM/YYYY.
  WRITE: / 'Período a ser aberto (MMPV):', lv_periodo_mmpv.
  WRITE: / 'Exercício para o período (MMPV):', lv_exercicio_mmpv.
  WRITE: / 'Código da Empresa:', p_bukrs.

  *--------------------------------------------------------------------*
  *   2. Construção da Sessão Batch Input para MMPV
  *--------------------------------------------------------------------*
  CLEAR lt_bdcdata.

  " Ecrã inicial da MMPV (SAPMM07M, Dynpro 0100)
  CLEAR ls_bdcdata.
  ls_bdcdata-program  = 'SAPMM07M'.
  ls_bdcdata-dynpro   = '0100'.
  ls_bdcdata-dynbegin = 'X'.
  APPEND ls_bdcdata TO lt_bdcdata.

  " Código da Empresa
  CLEAR ls_bdcdata.
  ls_bdcdata-fnam     = 'RMMZU-BUKRS'.
  ls_bdcdata-fval     = p_bukrs.
  APPEND ls_bdcdata TO lt_bdcdata.

  " Período
  CLEAR ls_bdcdata.
  ls_bdcdata-fnam     = 'RMMZU-POPER'.
  ls_bdcdata-fval     = lv_periodo_mmpv.
  APPEND ls_bdcdata TO lt_bdcdata.

  " Exercício
  CLEAR ls_bdcdata.
  ls_bdcdata-fnam     = 'RMMZU-POJAHR'.
  ls_bdcdata-fval     = lv_exercicio_mmpv.
  APPEND ls_bdcdata TO lt_bdcdata.

  " Opção "Verificar e diferir" (RM07MMVU-XVERD)
  " Se p_test for verdadeiro (abap_true), então XVERD = 'X'
  IF p_test = abap_true.
    CLEAR ls_bdcdata.
    ls_bdcdata-fnam     = 'RM07MMVU-XVERD'.
    ls_bdcdata-fval     = 'X'. " Marcar "Verificar e diferir"
    APPEND ls_bdcdata TO lt_bdcdata.
  ENDIF.

  " Código de Função para executar (ENTER ou botão específico)
  " O FCODE para executar é '=AUSF' (Ausführen / Execute)
  CLEAR ls_bdcdata.
  ls_bdcdata-fnam     = 'BDC_OKCODE'.
  ls_bdcdata-fval     = '=AUSF'.
  APPEND ls_bdcdata TO lt_bdcdata.

  *--------------------------------------------------------------------*
  *   3. Submissão da Sessão Batch Input
  *--------------------------------------------------------------------*
  DATA: lt_messtab TYPE TABLE OF bdcmsgcoll,
        ls_messtab TYPE bdcmsgcoll.

  CALL TRANSACTION 'MMPV' USING lt_bdcdata
                         MODE  'N' " N - Background, A - Display all, E - Display errors
                         UPDATE 'S' " S - Synchronous, A - Asynchronous
                         MESSAGES INTO lt_messtab.

  IF sy-subrc = 0.
    WRITE: / 'Transação MMPV (simulada ou executada) com sucesso.'.
    LOOP AT lt_messtab INTO ls_messtab WHERE msgtyp CA 'SEA'. " Sucesso, Erro, Aviso
      WRITE: / ls_messtab-msgtyp, ls_messtab-msgspra, ls_messtab-msgnr,
               ls_messtab-msgv1, ls_messtab-msgv2, ls_messtab-msgv3, ls_messtab-msgv4.
    ENDLOOP.
  ELSE.
    WRITE: / 'Erro ao submeter a transação MMPV. Subrc:', sy-subrc.
    LOOP AT lt_messtab INTO ls_messtab WHERE msgtyp CA 'EA'. " Erro, Aviso
      WRITE: / ls_messtab-msgtyp, ls_messtab-msgspra, ls_messtab-msgnr,
               ls_messtab-msgv1, ls_messtab-msgv2, ls_messtab-msgv3, ls_messtab-msgv4.
    ENDLOOP.
  ENDIF.

  IF p_test = abap_true.
    WRITE: / 'Executado em modo "Verificar e diferir". Nenhuma alteração real foi feita.'.
  ELSE.
    WRITE: / 'Executado em modo real. Alterações foram processadas.'.
  ENDIF.
