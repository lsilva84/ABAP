CLASS zcl_hr_rest_rp_02 DEFINITION
  PUBLIC
  INHERITING FROM cl_rest_resource
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    METHODS if_rest_resource~get
        REDEFINITION .
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zcl_hr_rest_rp_02 IMPLEMENTATION.


  METHOD if_rest_resource~get.

    TYPES:
      BEGIN OF lw_subordinados,
        i_num_func     TYPE pernr_d,
        e_subordinados TYPE zthr_lis_funcs_subor,
      END OF lw_subordinados.

    " Tipos para a nova lista de objetos com dados de teletrabalho
    TYPES:
      BEGIN OF ty_nova_lista_item,
        pernr      TYPE pernr_d,
        endda      TYPE datum,
        zzteletrab TYPE char1,
        zzregime   TYPE char20,
        zzmotivo   TYPE char40,
        zzdias     TYPE numc2,
      END OF ty_nova_lista_item.
    TYPES:
      ty_t_nova_lista TYPE STANDARD TABLE OF ty_nova_lista_item WITH EMPTY KEY.


    DATA: lv_string                     TYPE string,
          lv_e_retorno                  TYPE string,
          lv_e_unidades_organizacionais TYPE string,
          lv_e_posicoes                 TYPE string,
          lv_e_chefias                  TYPE string,
          lv_e_competencias             TYPE string.

    DATA: i_user                     TYPE xubname,
          i_id_key                   TYPE zuced03,
          e_retorno                  TYPE ztws_retorno,
          e_unidades_organizacionais TYPE zthr_unidades_organizacionais,
          e_posicoes                 TYPE zthr_posicoes_estrutura,
          e_chefias                  TYPE zthr_chefias_uo,
          e_chefias_aux              TYPE zthr_chefias_uo,
          e_competencias             TYPE zthr_competencias,
          i_exp_posicoes             TYPE char1,
          i_exp_chefias              TYPE char1,
          i_exp_competencias         TYPE char1,
          i_exp_subordinados         TYPE char1,
          e_subordinados             TYPE zthr_lis_funcs_subor,
          e_chefe_subordinados       TYPE TABLE OF lw_subordinados,
          l_chefe_subordinados       TYPE lw_subordinados,
          e_nova_lista               TYPE ty_t_nova_lista. " Variável para a nova lista

    TYPES:
      BEGIN OF lw_json_result,
        e_unidades_organizacionais TYPE zthr_unidades_organizacionais,
        e_posicoes                 TYPE zthr_posicoes_estrutura,
        e_chefias                  TYPE zthr_chefias_uo,
        e_competencias             TYPE zthr_competencias,
        e_chefe_subordinados       LIKE e_chefe_subordinados,
        e_nova_lista               TYPE ty_t_nova_lista, " Novo campo na estrutura do JSON
      END OF lw_json_result.



    "vai no header

    i_id_key = mo_request->get_header_field( iv_name = 'i_id_key' ).
    IF i_id_key IS INITIAL.
      mo_response->create_entity( )->set_string_data(
         iv_data = '{"Tipo":"E", "Mensagem":"Falta no header o campo -- i_id_key -- "}' ).
      EXIT.
    ENDIF.

    i_user = mo_request->get_header_field( iv_name = 'i_user' ).
    IF i_user IS INITIAL.
      mo_response->create_entity( )->set_string_data(
         iv_data = '{"Tipo":"E", "Mensagem":"Falta no header o campo -- i_user -- "}' ).
      EXIT.
    ENDIF.

    i_exp_posicoes = mo_request->get_header_field( iv_name = 'i_exp_posicoes' ).
    i_exp_chefias = mo_request->get_header_field( iv_name = 'i_exp_chefias' ).
    i_exp_competencias = mo_request->get_header_field( iv_name = 'i_exp_competencias' ).

    "Se é para exportar subordinados tem de ter o campo i_num_func preenchido
    i_exp_subordinados = mo_request->get_header_field( iv_name = 'i_exp_subordinados' ).
    IF i_exp_subordinados IS NOT INITIAL AND ( i_exp_posicoes IS INITIAL AND i_exp_chefias IS INITIAL AND i_exp_competencias IS INITIAL ).
      i_exp_chefias = 'X'.
    ELSEIF i_exp_subordinados IS NOT INITIAL.
      mo_response->create_entity( )->set_string_data(
            iv_data = '{"Tipo":"E", "Mensagem":"Quando escolhe a opção |i_exp_subordinados| as outras opções não podem ser selecionadas."}' ).
      EXIT.
    ENDIF.



    CALL FUNCTION 'ZHR_WS064'
      EXPORTING
        i_user                     = i_user
        i_id_key                   = i_id_key                " Id Key Aplicação Externa
        i_exp_posicoes             = i_exp_posicoes              " Código de uma posição
        i_exp_chefias              = i_exp_chefias             " Código de uma posição
        i_exp_competencias         = i_exp_competencias              " Código de uma posição
      IMPORTING
        e_retorno                  = e_retorno             " Categoria de Tabela de Lista de Resultados de Web Services
        e_unidades_organizacionais = e_unidades_organizacionais                " Categoria de Tabela das Unidades Organizacionais
        e_posicoes                 = e_posicoes                " Categoria de Tabela das Posições da Estrutura Organizacional
        e_chefias                  = e_chefias               " Categoria de Tabela das Chefias da Estrutura Organizacional
        e_competencias             = e_competencias.                 " Categoria de Tabela das Competencias/Tarefas


    MOVE-CORRESPONDING e_chefias TO e_chefias_aux.
    SORT e_chefias_aux BY numero_funcionario.
    DELETE ADJACENT DUPLICATES FROM e_chefias_aux COMPARING numero_funcionario.

    IF i_exp_subordinados IS NOT INITIAL.
      LOOP AT e_chefias_aux INTO DATA(wa).
        "Obtem lista de subordinados de um determinado funcionário/chefe
        CALL FUNCTION 'ZHR_WS010'
          EXPORTING
            i_user         = i_user
            i_num_func     = wa-numero_funcionario              " Seleções standard para reporting de dados mestre HR
            i_id_key       = i_id_key                           " Id Key Aplicação Externa
          IMPORTING
            e_subordinados = e_subordinados.                    " Categoria de Tabela p listagem de Subordinaddos Funcionários


        LOOP AT e_subordinados INTO DATA(wa_sub).
          SELECT SINGLE pernr FROM pa0001
            INTO @DATA(l_pernr)
            WHERE pernr = @wa_sub-num_func
              AND ( persg = '5' OR  persg = '2' OR ( persg = '7' AND persk = '76' ) )
              AND begda <= @sy-datum
              AND endda >= @sy-datum..
          IF sy-subrc NE 0.
            "para não retirar os chefes das listagens de subordinados
            LOOP AT e_chefias_aux INTO DATA(wa_aux) WHERE numero_funcionario EQ wa_sub-num_func.
              EXIT.
            ENDLOOP.
            IF sy-subrc NE 0.
              DELETE e_subordinados WHERE num_func = wa_sub-num_func.
            ENDIF.

          ENDIF.
        ENDLOOP.
        MOVE-CORRESPONDING e_subordinados TO l_chefe_subordinados-e_subordinados.
        l_chefe_subordinados-i_num_func = wa-numero_funcionario.
        APPEND l_chefe_subordinados TO e_chefe_subordinados.
      ENDLOOP.
    ENDIF.

    """"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
    " Para alterar o competencias no UCTeleWork vamos retirar todas as competencias
    " menos as novas criadas
    " AutET (AutMF)
    " ParET (ParMF)
    " ObsET (ObsMF)
    " ObsGeralET (ObsGeralMF)
    " Para não ter de alterar no backend e no frontend

    """"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
    IF e_competencias IS NOT INITIAL.
      DELETE e_competencias
      WHERE sigla_competencia  NE 'AutET'
         AND sigla_competencia NE 'ParET'
         AND sigla_competencia NE 'ObsET'
         AND sigla_competencia NE 'ObsGeralET'
         AND sigla_competencia NE 'DelAutET'
         AND sigla_competencia NE 'AutDelET'.

      LOOP AT e_competencias ASSIGNING FIELD-SYMBOL(<wa_comp>) .
        CASE <wa_comp>-sigla_competencia.
          WHEN 'AutET' .
            <wa_comp>-sigla_competencia  = 'AutMF'.
          WHEN 'ParET' .
            <wa_comp>-sigla_competencia  = 'ParMF'.
          WHEN 'ObsET' .
            <wa_comp>-sigla_competencia  = 'ObsMF'.
          WHEN 'ObsGeralET' .
            <wa_comp>-sigla_competencia  = 'ObsGeralMF'.
          WHEN 'DelAutET' .
            <wa_comp>-sigla_competencia  = 'DelAutMF'.
          WHEN 'AutDelET' .
            <wa_comp>-sigla_competencia  = 'AutDelMF'.

        ENDCASE.

      ENDLOOP.
    ENDIF.


    " Recolher todos os PERNRs para a consulta
    DATA lt_pernrs TYPE RANGE OF pernr_d.

    LOOP AT e_chefias INTO DATA(wa_chefe).
      APPEND VALUE #( sign = 'I' option = 'EQ' low = wa_chefe-numero_funcionario ) TO lt_pernrs.
    ENDLOOP.

    LOOP AT e_chefe_subordinados INTO DATA(wa_chefe_sub).
      APPEND VALUE #( sign = 'I' option = 'EQ' low = wa_chefe_sub-i_num_func ) TO lt_pernrs.
      LOOP AT wa_chefe_sub-e_subordinados INTO DATA(wa_sub).
        APPEND VALUE #( sign = 'I' option = 'EQ' low = wa_sub-num_func ) TO lt_pernrs.
      ENDLOOP.
    ENDLOOP.

    SORT lt_pernrs BY low.
    DELETE ADJACENT DUPLICATES FROM lt_pernrs COMPARING low.

    IF lt_pernrs IS NOT INITIAL.
      " Selecionar dados de teletrabalho da PA0007
      SELECT pernr, endda, zzteletrab, zzregime, zzmotivo, zzdias
        FROM pa0007
        FOR ALL ENTRIES IN @lt_pernrs
        WHERE pernr = @lt_pernrs-low
          AND zzteletrab = 'X'
        INTO TABLE @e_nova_lista.
    ENDIF.

    DATA(lst_json) = VALUE lw_json_result( e_unidades_organizacionais   = e_unidades_organizacionais
                                           e_posicoes                   = e_posicoes
                                           e_chefias                    = e_chefias
                                           e_competencias               = e_competencias
                                           e_chefe_subordinados         = e_chefe_subordinados
                                           e_nova_lista                 = e_nova_lista ). " Adicionar a nova lista à estrutura de resposta

    " adicionar uma nova key com uma lista de objetos

    /ui2/cl_json=>serialize( EXPORTING data = lst_json RECEIVING r_json = lv_string ).

    mo_response->create_entity( )->set_string_data( iv_data = lv_string  ).

    mo_response->set_header_field(
      EXPORTING
        iv_name  = 'Content-Type'
        iv_value = 'application/json'
    ).


  ENDMETHOD.
ENDCLASS.
