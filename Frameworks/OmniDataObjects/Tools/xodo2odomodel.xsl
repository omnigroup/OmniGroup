<?xml version="1.0"?>
<!--
	A XSL converter from the .xodo format to the Ruby DSL model format.

	Run with:

	xsltproc -o foo.odomodel -param ModelName "'MyModelName'" xodo2odomodel.xsl foo.xodo
-->

<xsl:stylesheet version="1.0"
	xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:odo="http://www.omnigroup.com/namespace/xodo/1.0">
	<xsl:output method="text" encoding="UTF-8" indent="no"/>

	<xsl:variable name="NL">
		<xsl:text>&#10;</xsl:text>
	</xsl:variable>

	<xsl:template match="odo:model">
		<xsl:text>model "</xsl:text>
		<xsl:value-of select="$ModelName"/>
		<xsl:text>" do</xsl:text>
	    <xsl:apply-templates/>
		<xsl:text>end</xsl:text>
	</xsl:template>
	
	<xsl:template match="odo:entity">
		<xsl:text>entity "</xsl:text>
		<xsl:value-of select="@name"/>
		<xsl:text>" do</xsl:text>
	    <xsl:apply-templates/>
		<xsl:text>end</xsl:text>
		<xsl:value-of select="$NL"/>
	</xsl:template>
	
	<xsl:template match="odo:attribute">
		<xsl:text>attribute "</xsl:text>
		<xsl:value-of select="@name"/>
		<xsl:text>", :</xsl:text>
		<xsl:value-of select="@type"/>
		<xsl:if test="@primary='true'">
			<xsl:text>, :primary =&gt; true</xsl:text>
		</xsl:if>
		<xsl:if test="@optional='true'">
			<xsl:text>, :optional =&gt; true</xsl:text>
		</xsl:if>
		<xsl:if test="@default != ''">
			<xsl:text>, :default =&gt; </xsl:text>
			<xsl:value-of select="@default"/>
		</xsl:if>
		<xsl:if test="@transient='true'">
			<xsl:text>, :transient =&gt; true</xsl:text>
		</xsl:if>
	</xsl:template>
	
	<xsl:template match="odo:relationship">
		<xsl:text>relationship "</xsl:text>
		<xsl:value-of select="@name"/>
		<xsl:text>", "</xsl:text>
		<xsl:value-of select="@entity"/>
		<xsl:text>", "</xsl:text>
		<xsl:value-of select="@inverse"/>
		<xsl:text>"</xsl:text>
		<xsl:if test="@optional='true'">
			<xsl:text>, :optional =&gt; true</xsl:text>
		</xsl:if>
		<xsl:if test="@many='true'">
			<xsl:text>, :many =&gt; true</xsl:text>
		</xsl:if>
		<xsl:if test="@delete != ''">
			<xsl:text>, :delete =&gt; :</xsl:text>
			<xsl:value-of select="@delete"/>
		</xsl:if>
	</xsl:template>
	

</xsl:stylesheet>
