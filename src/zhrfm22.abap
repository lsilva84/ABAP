FUNCTION ZHRFM22
  EXPORTING
    E_ERRO TYPE BINPT_FUNC
    E_RETORNO TYPE ZTWS_RETORNO_C
  TABLES
    T_ESTRUTURA LIKE ZLHR_UNIDADES_ORG_PT_EN
    RETURN LIKE BAPIRET2.

  TYPES:
    BEGIN OF ty_response,
      pureid TYPE i,
      uuid   TYPE string,
    END OF ty_response.

  TYPES: BEGIN OF ty_name,
           first_name TYPE string,
           last_name  TYPE string,
         END OF ty_name,
         BEGIN OF ty_description,
           en_gb TYPE string,
           pt_pt TYPE string,
         END OF ty_description,
         BEGIN OF ty_type,
           uri  TYPE string,
           term TYPE ty_description,
         END OF ty_type,
         BEGIN OF ty_organization,
           system_name TYPE string,
           uuid        TYPE string,
         END OF ty_organization,
         BEGIN OF ty_period,
           start_date TYPE string,
         END OF ty_period,
         BEGIN OF ty_st_org_ass,
           type_discriminator TYPE string,
           organization       TYPE ty_organization,
           period             TYPE ty_period,
         END OF ty_st_org_ass,
         BEGIN OF ty_visibility,
           key         TYPE string,
           description TYPE ty_description,
         END OF ty_visibility,
         BEGIN OF ty_identifiers,
           typediscriminator TYPE string,
           id                TYPE string,
           type_             TYPE ty_type,
         END OF ty_identifiers,
         BEGIN OF ty_data,
           name          TYPE ty_name,
           staff_org_ass TYPE STANDARD TABLE OF ty_st_org_ass WITH EMPTY KEY,
           visibility    TYPE ty_visibility,
           identifiers   TYPE STANDARD TABLE OF ty_identifiers WITH EMPTY KEY,
         END OF ty_data.

  DATA: ls_name          TYPE ty_name,
        ls_organization  TYPE ty_organization,
        ls_period        TYPE ty_period,
        ls_staff_org_ass TYPE ty_st_org_ass,
        ls_visibility    TYPE ty_visibility,
        ls_identifiers   TYPE ty_identifiers,
        ls_data          TYPE ty_data,
        ls_zhrtb85       TYPE zhrtb85.

  DATA: lt_response TYPE ty_response.

  DATA: lv_url      TYPE string VALUE 'https://research-test.uc.pt/ws/api/persons',
        lv_api_key  TYPE string VALUE 'f', " API Key Omitida intencionalmente
        lv_response TYPE string,
        lv_code     TYPE i,
        lv_reason   TYPE string.

  DATA : lo_http_client  TYPE REF TO if_http_client,
         lo_http_request TYPE REF TO if_http_entity.

  SELECT pa0~pernr, pa2~vorna, pa2~nachn ,pa1~persg, pa0~stat2, pa0~begda, zhr83~uo ,pa1~persk , zhr83~variante
      INTO TABLE  @DATA(lt_dados)
      FROM zhrtb83 AS zhr83
      INNER JOIN  hrp1001 AS hrp1
          ON hrp1~objid EQ zhr83~uo
          AND hrp1~sclas EQ 'S'
          AND hrp1~plvar EQ zhr83~variante
      INNER JOIN  hrp1001 AS hrp11
          ON hrp11~objid EQ hrp1~sobid
          AND hrp11~sclas EQ 'P'
      INNER JOIN pa0001 AS pa1
          ON  pa1~pernr EQ hrp11~sobid
      INNER JOIN pa0000 AS pa0
          ON pa0~pernr EQ pa1~pernr
      INNER JOIN pa0002 AS pa2
          ON pa2~pernr EQ pa1~pernr
      WHERE pa0~begda  LE @sy-datum
        AND pa0~endda  GE @sy-datum
        AND pa1~begda  LE @sy-datum
        AND pa1~endda  GE @sy-datum
        AND pa2~begda  LE @sy-datum
        AND pa2~endda  GE @sy-datum
        AND hrp1~begda LE @sy-datum
        AND hrp1~endda GE @sy-datum
        AND hrp11~begda LE @sy-datum
        AND hrp11~endda GE @sy-datum
       AND pa0~stat2 EQ 3.

  DATA(lt_dados2) = lt_dados.
  DELETE lt_dados WHERE variante NE 'PU'.
  SORT lt_dados BY pernr uo.
  DELETE ADJACENT DUPLICATES FROM lt_dados COMPARING pernr uo.

  SELECT * FROM zhrtb85 INTO TABLE @DATA(lt_zhrtb85_all). " Renomeado para evitar conflito
  SORT lt_zhrtb85_all BY pernr uo.

  CALL FUNCTION 'ZHRFM23'
    EXPORTING
      i_uo_inicial = 'UC'
      i_variante   = 'UC'
    TABLES
      t_estrutura  = t_estrutura.

  IF lt_dados IS NOT INITIAL.
    SELECT pa0~pernr, pa2~vorna, pa2~nachn, pa1~persg, pa0~stat2,
           pa0~begda, pa1~persk, hrp1~objid , hrp11~sclas
    INTO TABLE @DATA(lt_dados_2)
    FROM hrp1001 AS hrp1
    INNER JOIN hrp1001 AS hrp11
        ON hrp11~objid EQ hrp1~sobid
    INNER JOIN pa0001 AS pa1
        ON pa1~pernr EQ hrp11~sobid
    INNER JOIN pa0000 AS pa0
        ON pa0~pernr EQ pa1~pernr
    INNER JOIN pa0002 AS pa2
        ON pa2~pernr EQ pa1~pernr
    FOR ALL ENTRIES IN @lt_dados
    WHERE pa0~pernr EQ @lt_dados-pernr
      AND pa0~begda  LE @sy-datum
      AND pa0~endda  GE @sy-datum
      AND pa1~begda  LE @sy-datum
      AND pa1~endda  GE @sy-datum
      AND pa2~begda  LE @sy-datum
      AND pa2~endda  GE @sy-datum
      AND hrp1~begda LE @sy-datum
      AND hrp1~endda GE @sy-datum
      AND hrp11~begda LE @sy-datum
      AND hrp11~endda GE @sy-datum
      AND hrp1~plvar EQ 'UC'
      AND hrp11~sclas EQ 'P'
      AND hrp11~otype EQ 'S'
      AND hrp11~plvar EQ 'UC'
      AND hrp11~rsign EQ 'A'
      AND hrp11~relat EQ '008'
      AND pa0~stat2 EQ 3.
  ENDIF.

  LOOP AT lt_dados INTO DATA(ls_dados_loop_var). " Renomeado para evitar conflito com ls_dados do AT NEW
    DATA(index) = sy-tabix.
    CALL FUNCTION 'CONVERSION_EXIT_ALPHA_OUTPUT'
      EXPORTING
        input  = ls_dados_loop_var-pernr
      IMPORTING
        output = ls_dados_loop_var-pernr.
    READ TABLE lt_zhrtb85_all INTO DATA(ls_zhrtb85_read) WITH KEY pernr = ls_dados_loop_var-pernr.
    IF sy-subrc EQ 0.
      DELETE lt_dados INDEX index.
    ENDIF.
  ENDLOOP.

  " Nova variável para acumular dados da pessoa atual
  DATA: ls_current_person_data TYPE ty_data.
  FIELD-SYMBOLS: <fs_retm> TYPE bapiret2.

  SORT lt_dados BY pernr uo. " Já ordenado, mas para garantir

  LOOP AT lt_dados INTO DATA(ls_dados_row).

    AT NEW pernr.
      CLEAR ls_current_person_data.

      ls_current_person_data-name-first_name = ls_dados_row-vorna.
      ls_current_person_data-name-last_name = ls_dados_row-nachn.

      DATA(temp_ls_visibility) TYPE ty_visibility.
      temp_ls_visibility-key = 'FREE'.
      temp_ls_visibility-description-en_gb = 'Public - No restriction'.
      temp_ls_visibility-description-pt_pt = '???visibility.FREE???'.
      ls_current_person_data-visibility = temp_ls_visibility.

      DATA(temp_ls_identifiers) TYPE ty_identifiers.
      DATA(lv_pernr_alpha_out) TYPE string.
      CALL FUNCTION 'CONVERSION_EXIT_ALPHA_OUTPUT'
        EXPORTING
          input  = ls_dados_row-pernr
        IMPORTING
          output = lv_pernr_alpha_out.

      CONCATENATE 'uc' lv_pernr_alpha_out '@uc.pt' INTO temp_ls_identifiers-id.
      temp_ls_identifiers-typediscriminator = 'ClassifiedId'.
      temp_ls_identifiers-type_-uri = '/dk/atira/pure/person/personsources/employee'.
      temp_ls_identifiers-type_-term-en_gb = 'Employee ID'.
      temp_ls_identifiers-type_-term-pt_pt = 'ID de funcionário'.
      APPEND temp_ls_identifiers TO ls_current_person_data-identifiers.
    ENDATNEW.

    DATA(temp_ls_organization) TYPE ty_organization.
    DATA(temp_ls_period) TYPE ty_period.
    DATA(ls_staff_org_ass_entry) TYPE ty_st_org_ass.

    temp_ls_organization-system_name = 'Organization'.
    TRY.
        SELECT SINGLE uuid FROM zhrtb83 INTO temp_ls_organization-uuid WHERE uo = ls_dados_row-uo.
      CATCH cx_sql_exception.
        " TODO: Rever esta lógica de fallback. Pode atribuir UUID errado.
        SELECT SINGLE uuid FROM zhrtb83 INTO temp_ls_organization-uuid .
    ENDTRY.

    CONCATENATE ls_dados_row-begda+0(4) '-' ls_dados_row-begda+4(2) '-' ls_dados_row-begda+6(2) INTO temp_ls_period-start_date.

    ls_staff_org_ass_entry-type_discriminator = 'StaffOrganizationAssociation'.
    ls_staff_org_ass_entry-organization = temp_ls_organization.
    ls_staff_org_ass_entry-period = temp_ls_period.
    APPEND ls_staff_org_ass_entry TO ls_current_person_data-staff_org_ass.

    AT END OF pernr.
      DATA(lv_json_payload) TYPE string.
      CALL METHOD /ui2/cl_json=>serialize
        EXPORTING
          data   = ls_current_person_data
        RECEIVING
          r_json = lv_json_payload.

      REPLACE ALL OCCURRENCES OF 'FIRST_NAME' IN lv_json_payload WITH 'firstName'.
      REPLACE ALL OCCURRENCES OF 'LAST_NAME' IN lv_json_payload WITH 'lastName'.
      REPLACE ALL OCCURRENCES OF 'SYSTEM_NAME' IN lv_json_payload WITH 'systemName'.
      REPLACE ALL OCCURRENCES OF 'NAME' IN lv_json_payload WITH 'name'.
      REPLACE ALL OCCURRENCES OF 'STAFF_ORG_ASS' IN lv_json_payload WITH 'staffOrganizationAssociations'.
      REPLACE ALL OCCURRENCES OF 'TYPE_DISCRIMINATOR' IN lv_json_payload WITH 'typeDiscriminator'.
      REPLACE ALL OCCURRENCES OF 'ORGANIZATION' IN lv_json_payload WITH 'organization'.
      REPLACE ALL OCCURRENCES OF 'UUID' IN lv_json_payload WITH 'uuid'.
      REPLACE ALL OCCURRENCES OF 'PERIOD' IN lv_json_payload WITH 'period'.
      REPLACE ALL OCCURRENCES OF 'START_DATE' IN lv_json_payload WITH 'startDate'.
      REPLACE ALL OCCURRENCES OF 'VISIBILITY' IN lv_json_payload WITH 'visibility'.
      REPLACE ALL OCCURRENCES OF 'KEY' IN lv_json_payload WITH 'key'.
      REPLACE ALL OCCURRENCES OF 'DESCRIPTION' IN lv_json_payload WITH 'description'.
      REPLACE ALL OCCURRENCES OF 'EN_GB' IN lv_json_payload WITH 'en_GB'.
      REPLACE ALL OCCURRENCES OF 'PT_PT' IN lv_json_payload WITH 'pt_PT'.
      REPLACE ALL OCCURRENCES OF 'IDENTIFIERS' IN lv_json_payload WITH 'identifiers'.
      REPLACE ALL OCCURRENCES OF 'TYPEDISCRIMINATOR' IN lv_json_payload WITH 'typeDiscriminator'.
      REPLACE ALL OCCURRENCES OF 'TYPE_' IN lv_json_payload WITH 'type'.
      REPLACE ALL OCCURRENCES OF 'URI' IN lv_json_payload WITH 'uri'.
      REPLACE ALL OCCURRENCES OF 'TERM' IN lv_json_payload WITH 'term'.
      REPLACE ALL OCCURRENCES OF 'ID' IN lv_json_payload WITH 'id'.

      DATA(lo_http_client_loop) TYPE REF TO if_http_client.
      DATA(lv_response_loop) TYPE string.
      DATA(lt_response_loop) TYPE ty_response.
      DATA(lv_http_error_message) TYPE string.


      TRY.
          CALL METHOD cl_http_client=>create_by_url
            EXPORTING
              url                = lv_url
            IMPORTING
              client             = lo_http_client_loop
            EXCEPTIONS
              argument_not_found = 1  plugin_not_active  = 2
              internal_error     = 3  OTHERS             = 4.
          IF sy-subrc <> 0.
            lv_http_error_message = |Erro ({ sy-subrc }) ao criar cliente HTTP para { ls_dados_row-pernr }|.
            APPEND INITIAL LINE TO return ASSIGNING <fs_retm>.
            <fs_retm>-type = 'E'. <fs_retm>-message = lv_http_error_message.
            CONTINUE.
          ENDIF.

          lo_http_client_loop->request->set_method('PUT').
          lo_http_client_loop->request->set_version( if_http_request=>co_protocol_version_1_1 ).
          lo_http_client_loop->request->if_http_entity~set_content_type( if_rest_media_type=>gc_appl_json ).
          lo_http_client_loop->request->set_header_field( name = 'Accept' value = '*/*' ).
          lo_http_client_loop->request->set_header_field( name = 'Content-Type' value = 'application/json' ).
          lo_http_client_loop->request->set_header_field( name = 'api-key' value = lv_api_key ).
          lo_http_client_loop->request->set_cdata( lv_json_payload ).

          lo_http_client_loop->send( EXPORTING timeout = 15 EXCEPTIONS http_communication_failure = 1 http_invalid_state = 2 http_processing_failed = 3 OTHERS = 4 ).
          IF sy-subrc <> 0.
            lv_http_error_message = |Erro ({ sy-subrc }) no envio HTTP para { ls_dados_row-pernr }|.
            APPEND INITIAL LINE TO return ASSIGNING <fs_retm>.
            <fs_retm>-type = 'E'. <fs_retm>-message = lv_http_error_message.
            lo_http_client_loop->close( ).
            CONTINUE.
          ENDIF.

          lo_http_client_loop->receive( EXCEPTIONS http_communication_failure = 1 http_invalid_state = 2 http_processing_failed = 3 OTHERS = 4 ).
          IF sy-subrc <> 0.
            lv_http_error_message = |Erro ({ sy-subrc }) na recepção HTTP para { ls_dados_row-pernr }|.
            APPEND INITIAL LINE TO return ASSIGNING <fs_retm>.
            <fs_retm>-type = 'E'. <fs_retm>-message = lv_http_error_message.
            lo_http_client_loop->close( ).
            CONTINUE.
          ENDIF.

          lv_response_loop = lo_http_client_loop->response->get_cdata( ).
          lo_http_client_loop->close( ).

          CALL METHOD /ui2/cl_json=>deserialize EXPORTING json = lv_response_loop CHANGING data = lt_response_loop.

          DATA(ls_zhrtb85_update) TYPE zhrtb85.
          ls_zhrtb85_update-pureid = lt_response_loop-pureid.
          ls_zhrtb85_update-uuid = lt_response_loop-uuid.
          ls_zhrtb85_update-pernr = ls_dados_row-pernr. " This should be from ls_current_person_data or a variable saved at AT NEW
          CONCATENATE ls_current_person_data-name-first_name ls_current_person_data-name-last_name
              INTO ls_zhrtb85_update-name SEPARATED BY space.

          SELECT SINGLE pernr FROM zhrtb85 INTO @DATA(lv_existing_pernr) WHERE pernr = @ls_zhrtb85_update-pernr.
          IF sy-subrc = 0.
              UPDATE zhrtb85 FROM @ls_zhrtb85_update WHERE pernr = @ls_zhrtb85_update-pernr.
          ELSE.
              INSERT zhrtb85 FROM @ls_zhrtb85_update.
          ENDIF.
          IF sy-subrc <> 0.
            APPEND INITIAL LINE TO return ASSIGNING <fs_retm>.
            <fs_retm>-type = 'E'. <fs_retm>-message = |Erro BD ({ sy-subrc }) ZHRTB85 para { ls_dados_row-pernr }|.
          ENDIF.

          CALL FUNCTION 'ZUCFM03'
            EXPORTING
              i_tipo_mensagem = 'S'
              i_n_mensagem    = '999'
              i_mensagem_1    = CONV syst_msgv( ls_dados_row-pernr ) " This should be from a variable holding current pernr
              i_mensagem_2    = CONV syst_msgv( lt_response_loop-uuid )
              i_mensagem_3    = CONV syst_msgv( lt_response_loop-pureid )
              i_aplicacao     = 'ZUC'
              i_identificacao = CONV balsubobj( ls_dados_row-pernr ) " This should be from a variable holding current pernr
              i_objeto_log    = 'ZUC'
            IMPORTING
              e_erro          = DATA(e_erro_log)
              e_retorno       = DATA(e_retorno_log).
          IF e_erro_log IS NOT INITIAL.
             " Log ZUCFM03 error
          ENDIF.

        CATCH cx_http_communication_error cx_http_invalid_state cx_http_processing_error INTO DATA(lx_http_error).
          lv_http_error_message = |Exceção HTTP ({ lx_http_error->get_text( ) }) para { ls_dados_row-pernr }|.
          APPEND INITIAL LINE TO return ASSIGNING <fs_retm>.
          <fs_retm>-type = 'E'. <fs_retm>-message = lv_http_error_message.
          IF lo_http_client_loop IS BOUND AND lo_http_client_loop->m_state <> lo_http_client_loop->co_state_closed.
            lo_http_client_loop->close( ).
          ENDIF.
        CATCH cx_sy_open_sql_db INTO DATA(lx_db_error).
            APPEND INITIAL LINE TO return ASSIGNING <fs_retm>.
            <fs_retm>-type = 'E'. <fs_retm>-message = |Exceção BD ({ lx_db_error->get_text( ) }) ZHRTB85 para { ls_dados_row-pernr }|.
        CATCH cx_sql_exception INTO DATA(lx_sql_error). " Para o SELECT SINGLE uuid
            APPEND INITIAL LINE TO return ASSIGNING <fs_retm>.
            <fs_retm>-type = 'E'. <fs_retm>-message = |Exceção SQL ({ lx_sql_error->get_text( ) }) ao ler UUID da UO para { ls_dados_row-pernr }|.
      ENDTRY.
    ENDATEND.
  ENDLOOP.
ENDFUNCTION.
